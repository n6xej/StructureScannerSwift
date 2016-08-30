//
//	This file is a Swift port of the Structure SDK sample app "Scanner".
//	Copyright © 2016 Occipital, Inc. All rights reserved.
//	http://structure.io
//
//  ViewController+SLAM.swift
//
//  Ported by Christopher Worley on 8/20/16.
//


func deltaRotationAngleBetweenPosesInDegrees(previousPose: GLKMatrix4, newPose: GLKMatrix4) -> Float {
	
	// Transpose is equivalent to inverse since we will only use the rotation part.
	let deltaPose: GLKMatrix4 = GLKMatrix4Multiply(newPose, GLKMatrix4Transpose(previousPose))
	
	// Get the rotation component of the delta pose
	let deltaRotationAsQuaternion = GLKQuaternionMakeWithMatrix4(deltaPose)
	
	// Get the angle of the rotation
	let angleInDegree = GLKQuaternionAngle(deltaRotationAsQuaternion) / Float(M_PI) * 180
	
	return angleInDegree
}

func computeTrackerMessage(hints: STTrackerHints) -> NSString? {
	
	if hints.trackerIsLost {
		return "Tracking Lost! Please Realign or Press Reset."
	}
	
	if hints.modelOutOfView {
		return "Please put the model back in view."
	}
	
	if hints.sceneIsTooClose {
		return "Too close to the scene! Please step back."
	}

	return nil
}

//MARK: - SLAM

extension ViewController {
	
    func setupSLAM() {
		
        if _slamState.initialized {
            return
        }

        // Initialize the scene.
        _slamState.scene = STScene.init(context: _display!.context, freeGLTextureUnit: GLenum(GL_TEXTURE2))
		
        // Initialize the camera pose tracker.
        let trackerOptions: [NSObject : AnyObject] = [kSTTrackerTypeKey: _dynamicOptions.newTrackerIsOn ? STTrackerType.DepthAndColorBased.rawValue : STTrackerType.DepthBased.rawValue, kSTTrackerTrackAgainstModelKey: true, kSTTrackerQualityKey: STTrackerQuality.Accurate.rawValue, kSTTrackerBackgroundProcessingEnabledKey: true]

        // Initialize the camera pose tracker.
        _slamState.tracker = STTracker.init(scene: _slamState.scene!, options: trackerOptions)
		
		// Default volume size set in options struct
		if _slamState.volumeSizeInMeters.x.isNaN {
			_slamState.volumeSizeInMeters = _options.initVolumeSizeInMeters
		}
		
		// The mapper will be initialized when we start scanning.
		
		// Setup the cube placement initializer.
		_slamState.cameraPoseInitializer = STCameraPoseInitializer.init(volumeSizeInMeters: _slamState.volumeSizeInMeters, options: [kSTCameraPoseInitializerStrategyKey: STCameraPoseInitializerStrategy.TableTopCube.rawValue])
		
		// Set up the cube renderer with the current volume size.
		_display!.cubeRenderer = STCubeRenderer.init(context: _display!.context)
		
		// Set up the initial volume size.
	
		adjustVolumeSize(volumeSize: _slamState.volumeSizeInMeters)
		
		// Start with cube placement mode
		enterCubePlacementState()

		let keyframeManagerOptions: [NSObject : AnyObject] = [
			kSTKeyFrameManagerMaxSizeKey : _options.maxNumKeyFrames,
			kSTKeyFrameManagerMaxDeltaTranslationKey : _options.maxKeyFrameTranslation,
			kSTKeyFrameManagerMaxDeltaRotationKey : _options.maxKeyFrameRotation] // 20 degrees.
		_slamState.prevFrameTimeStamp = -1.0
		_slamState.keyFrameManager = STKeyFrameManager.init(options: keyframeManagerOptions)
		
		_depthAsRgbaVisualizer = STDepthToRgba.init(options: [kSTDepthToRgbaStrategyKey: STDepthToRgbaStrategy.Gray.rawValue])
		
		_slamState.initialized = true
	}
    
    func resetSLAM() {

		if _slamState.tracker != nil && _slamState.scene != nil && _slamState.keyFrameManager != nil {
			_slamState.tracker!.reset()
			_slamState.scene!.clear()
            _slamState.prevFrameTimeStamp = -1.0
			_slamState.keyFrameManager!.clear()
		}

		if _slamState.mapper != nil {
			_slamState.mapper!.reset()
		}
		
		enterCubePlacementState()
    }
	
    func clearSLAM() {
        _slamState.initialized = false
        _slamState.scene = nil
        _slamState.tracker = nil
        _slamState.mapper = nil
        _slamState.keyFrameManager = nil
    }
	
	func setupMapper() {
		
		if _slamState.mapper != nil {
			_slamState.mapper = nil // make sure we first remove a previous mapper.
		}
		
		// Here, we set a larger volume bounds size when mapping in high resolution.
		let lowResolutionVolumeBounds: Float = 125
		let highResolutionVolumeBounds: Float = 200
		
		var voxelSizeInMeters: Float = _slamState.volumeSizeInMeters.x /
			(_dynamicOptions.highResMapping ? highResolutionVolumeBounds : lowResolutionVolumeBounds)
		
		// Avoid voxels that are too small - these become too noisy.
		voxelSizeInMeters = keepInRange(voxelSizeInMeters, minValue: 0.003, maxValue: 0.2)
		
		// Compute the volume bounds in voxels, as a multiple of the volume resolution.
		let volumeBounds = GLKVector3.init(v:
			(roundf(_slamState.volumeSizeInMeters.x / voxelSizeInMeters),
				roundf(_slamState.volumeSizeInMeters.y / voxelSizeInMeters),
				roundf(_slamState.volumeSizeInMeters.z / voxelSizeInMeters)
		))
		
		let msg = String.init(format: "[Mapper] volumeSize (m): %f %f %f volumeBounds: %.0f %.0f %.0f (resolution=%f m)",
		                      _slamState.volumeSizeInMeters.x, _slamState.volumeSizeInMeters.y, _slamState.volumeSizeInMeters.z,
		                      volumeBounds.x, volumeBounds.y, volumeBounds.z,
		                      voxelSizeInMeters )
		NSLog(msg)
		
		let mapperOptions: [NSObject: AnyObject] =
			[kSTMapperLegacyKey : !_dynamicOptions.newMapperIsOn,
			 kSTMapperVolumeResolutionKey : voxelSizeInMeters,
			 kSTMapperVolumeBoundsKey: [volumeBounds.x, volumeBounds.y, volumeBounds.z],
			 kSTMapperVolumeHasSupportPlaneKey: _slamState.cameraPoseInitializer!.hasSupportPlane,
			 kSTMapperEnableLiveWireFrameKey: false,
			 ]
		
		_slamState.mapper = STMapper.init(scene: _slamState.scene, options: mapperOptions)
	}
	
	func maybeAddKeyframeWithDepthFrame(depthFrame: STDepthFrame, colorFrame: STColorFrame?, depthCameraPoseBeforeTracking: GLKMatrix4) -> NSString? {
		
		if colorFrame == nil {
			return nil // nothing to do
		}

		// Only consider adding a new keyframe if the accuracy is high enough.
		if _slamState.tracker!.poseAccuracy.rawValue < STTrackerPoseAccuracy.Approximate.rawValue {
			return nil
		}
	
		let depthCameraPoseAfterTracking = _slamState.tracker!.lastFrameCameraPose
	
		// Make sure the pose is in color camera coordinates in case we are not using registered depth.
		var colorCameraPoseInDepthCoordinateSpace = GLKMatrix4.init()
        
        withUnsafeMutablePointer(&colorCameraPoseInDepthCoordinateSpace.m, {depthFrame.colorCameraPoseInDepthCoordinateFrame(UnsafeMutablePointer<Float>($0))})

		let colorCameraPoseAfterTracking = GLKMatrix4Multiply(depthCameraPoseAfterTracking(),colorCameraPoseInDepthCoordinateSpace)
	
		var showHoldDeviceStill = false
	
		// Check if the viewpoint has moved enough to add a new keyframe
		if _slamState.keyFrameManager!.wouldBeNewKeyframeWithColorCameraPose(colorCameraPoseAfterTracking) {
	
			let isFirstFrame = _slamState.prevFrameTimeStamp < 0
			
			var canAddKeyframe = false
	
			if isFirstFrame { // always add the first frame.
			
				canAddKeyframe = true
			}
			else { // for others, check the speed.
			
				var deltaAngularSpeedInDegreesPerSecond = FLT_MAX
				let deltaSeconds = depthFrame.timestamp - _slamState.prevFrameTimeStamp
	
				// If deltaSeconds is 2x longer than the frame duration of the active video device, do not use it either
				let frameDuration: CMTime = videoDevice!.activeVideoMaxFrameDuration
				
				if deltaSeconds < Double(frameDuration.value) / Double(frameDuration.timescale) * 2 {
				
					// Compute angular speed
					deltaAngularSpeedInDegreesPerSecond = deltaRotationAngleBetweenPosesInDegrees (depthCameraPoseBeforeTracking, newPose: depthCameraPoseAfterTracking()) / Float(deltaSeconds)
				}
	
				// If the camera moved too much since the last frame, we will likely end up
				// with motion blur and rolling shutter, especially in case of rotation. This
				// checks aims at not grabbing keyframes in that case.
				if CGFloat(deltaAngularSpeedInDegreesPerSecond) < _options.maxKeyframeRotationSpeedInDegreesPerSecond {
				
					canAddKeyframe = true
				}
			}
	
			if canAddKeyframe {
			
				_slamState.keyFrameManager!.processKeyFrameCandidateWithColorCameraPose(
					colorCameraPoseAfterTracking,
					colorFrame: colorFrame,
					depthFrame: nil) // Spare the depth frame memory, since we do not need it in keyframes.
			}
			else {
				// Moving too fast. Hint the user to slow down to capture a keyframe
				// without rolling shutter and motion blur.
				showHoldDeviceStill = true
			}
		}
	
		if showHoldDeviceStill {
			return "Please hold still so we can capture a keyframe..."
		}
	
		return nil
	}
	
	func updateMeshAlphaForPoseAccuracy(poseAccuracy: STTrackerPoseAccuracy) {
	
		switch (poseAccuracy) {
		
		case .High, .Approximate:
			
			_display!.meshRenderingAlpha = 0.8
			
		case .Low:
			
			_display!.meshRenderingAlpha = 0.4
			
		case .VeryLow, .NotAvailable:
			
			_display!.meshRenderingAlpha = 0.1;

		}
	}

    func processDepthFrame(depthFrame: STDepthFrame, colorFrame: STColorFrame?) {

		if _options.applyExpensiveCorrectionToDepth
		{
			assert(!_options.useHardwareRegisteredDepth, "Cannot enable both expensive depth correction and registered depth.")
			let couldApplyCorrection = depthFrame.applyExpensiveCorrection()
			if !couldApplyCorrection {
				print("Warning: could not improve depth map accuracy, is your firmware too old?");
			}
		}

        // Upload the new color image for next rendering.
        if _useColorCamera && colorFrame != nil {
            uploadGLColorTexture(colorFrame: colorFrame!)
        }
        else if !_useColorCamera {
            uploadGLColorTextureFromDepth(depthFrame)
        }
		
        // Update the projection matrices since we updated the frames.
        
        _display!.depthCameraGLProjectionMatrix = depthFrame.glProjectionMatrix()
        if colorFrame != nil {
            _display!.colorCameraGLProjectionMatrix = colorFrame!.glProjectionMatrix()
        }
        
        switch _slamState.scannerState {
			
        case .CubePlacement:
  
            var depthFrameForROIHighlighting: STDepthFrame = depthFrame

            if _useColorCamera  {
                depthFrameForROIHighlighting = depthFrame.registeredToColorFrame(colorFrame)
            }
            
            // Provide the new depth frame to the cube renderer for ROI highlighting.
            _display!.cubeRenderer!.setDepthFrame(depthFrameForROIHighlighting)
            
            // Estimate the new scanning volume position.
            if GLKVector3Length(_lastGravity) > 1e-5 {
                
                do {
                    try _slamState.cameraPoseInitializer?.updateCameraPoseWithGravity(_lastGravity, depthFrame: depthFrame)
                    
                } catch {
                    assertionFailure("Camera pose initializer error.")
                }
            }

            // Tell the cube renderer whether there is a support plane or not.
            _display!.cubeRenderer!.setCubeHasSupportPlane((_slamState.cameraPoseInitializer?.hasSupportPlane)!)
            
            // Enable the scan button if the pose initializer could estimate a pose.
            self.scanButton.enabled = _slamState.cameraPoseInitializer!.hasValidPose
            
            
        case .Scanning:
            // First try to estimate the 3D pose of the new frame.
			
			var trackingMessage: NSString? = nil
			
			var keyframeMessage: NSString? = nil
			
            let depthCameraPoseBeforeTracking: GLKMatrix4 = _slamState.tracker!.lastFrameCameraPose()
			
			// Integrate it into the current mesh estimate if tracking was successful.
            do {
                try _slamState.tracker!.updateCameraPoseWithDepthFrame(depthFrame, colorFrame: colorFrame)
				
				// Update the tracking message.
				trackingMessage = computeTrackerMessage(_slamState.tracker!.trackerHints)
				
				// Set the mesh transparency depending on the current accuracy.
				updateMeshAlphaForPoseAccuracy(_slamState.tracker!.poseAccuracy)
				
				// If the tracker accuracy is high, use this frame for mapper update and maybe as a keyframe too.
				if _slamState.tracker!.poseAccuracy.rawValue >= STTrackerPoseAccuracy.High.rawValue {
					_slamState.mapper?.integrateDepthFrame(depthFrame, cameraPose: (_slamState.tracker?.lastFrameCameraPose())!)
					}
				
					keyframeMessage = maybeAddKeyframeWithDepthFrame(depthFrame, colorFrame: colorFrame, depthCameraPoseBeforeTracking: depthCameraPoseBeforeTracking)
				
				// Tracking messages have higher priority.
				if  trackingMessage != nil {
					showTrackingMessage(trackingMessage as! String)
				}
				else if keyframeMessage != nil {
					showTrackingMessage(keyframeMessage as! String)
				}
				else {
					hideTrackingErrorMessage()
				}
				
            } catch let trackingError as NSError {
				NSLog("[Structure] STTracker Error: %@.", trackingError.localizedDescription)
				
				trackingMessage = trackingError.localizedDescription
            }
			
			_slamState.prevFrameTimeStamp = depthFrame.timestamp
		
			case .Viewing:
				break
			// Do nothing, the MeshViewController will take care of this.
		}
	}
}

//  Xcode would not see the ViewController class in IBuilder if the extension
//  was spread over more than 4 source files
//
//MARK: - Sensor Extension
//

extension ViewController: STSensorControllerDelegate {
    
    //MARK: -  Structure Sensor delegates
    
    func setupStructureSensor() {
        
        // Get the sensor controller singleton
        _sensorController = STSensorController.sharedController()
        
        // Set ourself as the delegate to receive sensor data.
        _sensorController.delegate = self
    }
    
    func isStructureConnectedAndCharged() -> Bool {
        
        return _sensorController.isConnected() && !_sensorController.isLowPower()
    }
    
    func sensorDidConnect() {
        
        NSLog("[Structure] Sensor connected!")
        
        if currentStateNeedsSensor() {
            connectToStructureSensorAndStartStreaming()
        }
        
        if !calibrationOverlay.hidden {
            calibrationOverlay.alpha = 1
        }
        
        if !instructionOverlay.hidden {
            instructionOverlay.alpha = 1
        }
    }
    
    func sensorDidLeaveLowPowerMode() {
        
        _appStatus.sensorStatus = .NeedsUserToConnect
        updateAppStatusMessage()
    }
    
    func sensorBatteryNeedsCharging() {
        
        // Notify the user that the sensor needs to be charged.
        _appStatus.sensorStatus = .NeedsUserToCharge
        updateAppStatusMessage()
    }
    
    func sensorDidStopStreaming(reason: STSensorControllerDidStopStreamingReason) {
        
        if reason == .AppWillResignActive {
            stopColorCamera()
            NSLog("[Structure] Stopped streaming because the app will resign its active state.")
        } else {
            NSLog("[Structure] Stopped streaming for an unknown reason.")
        }
    }
    
    func sensorDidDisconnect() {
        
        // If we receive the message while in background, do nothing. We'll check the status when we
        // become active again.
        
        if UIApplication.sharedApplication().applicationState != .Active {
            return
        }
        
        NSLog("[Structure] Sensor disconnected!")
        
        // Reset the scan on disconnect, since we won't be able to recover afterwards.
        if _slamState.scannerState == .Scanning {
            resetButtonPressed(scanButton)
        }
        
        if _useColorCamera {
            stopColorCamera()
        }
        // We only show the app status when we need sensor
        if currentStateNeedsSensor() {
            
            _appStatus.sensorStatus = .NeedsUserToConnect
            updateAppStatusMessage()
        }
        
        if !calibrationOverlay.hidden {
            calibrationOverlay.alpha = 0
        }
        
        if !instructionOverlay.hidden {
            instructionOverlay.alpha = 0
        }
        
        updateIdleTimer()
    }
    
    func connectToStructureSensorAndStartStreaming() -> STSensorControllerInitStatus {
        
        // Try connecting to a Structure Sensor.
        let result: STSensorControllerInitStatus = _sensorController.initializeSensorConnection()
        
        if result == .Success || result == .AlreadyInitialized {
            
            // Even though _useColorCamera was set in viewDidLoad by asking if an approximate calibration is guaranteed,
            // it's still possible that the Structure Sensor that has just been plugged in has a custom or approximate calibration
            // that we couldn't have known about in advance.
            
            let calibrationType = _sensorController.calibrationType()
            
            _useColorCamera = (calibrationType == .Approximate || calibrationType == .DeviceSpecific)
            
            if _useColorCamera {
                
                // Leave _dynamicOptions.newTrackerIsOn alone. It may have been modified by the user.
                
                // Enable the new tracker UI switch, since both depth and color frames can be captured.
                _dynamicOptions.newTrackerSwitchEnabled = true
                
                // Leave _dynamicOptions.highResColoring alone. It may have been modified by the user.
                
                // Enable the high-res coloring UI switch when high-resolution color capture is available.
                _dynamicOptions.highResColoringSwitchEnabled = videoDeviceSupportsHighResColor()
            } else {
                
                // Disable both the new tracker and its UI switch, since there is no color camera input.
                _dynamicOptions.newTrackerSwitchEnabled = false
                _dynamicOptions.newTrackerIsOn = false
                
                // Disable both the high resolution coloring and its UI switch, since there is no color camera input.
                _dynamicOptions.highResColoring = false
                _dynamicOptions.highResColoringSwitchEnabled = false
                
                // If we can't use the color camera, then don't try to use registered depth.
                _options.useHardwareRegisteredDepth = false
            }
            
            // Make sure the new mapper and high-resolution mapping switches are always enabled.
            _dynamicOptions.newMapperSwitchEnabled = true
            _dynamicOptions.highResMappingSwitchEnabled = true
            
            // Reset the SLAM pipeline.
            // This will also synchronize the UI switches states from the dynamic option values.
            onSLAMOptionsChanged()
            
            // Update the app status message.
            _appStatus.sensorStatus = .Ok
            updateAppStatusMessage()
            
            // Start streaming depth data.
            startStructureSensorStreaming()
        } else {
            switch (result) {
            case .SensorNotFound:
                NSLog("[Structure] No sensor found")
                
            case .OpenFailed:
                NSLog("[Structure] Error: Open failed.")
                
            case .SensorIsWakingUp:
                NSLog("[Structure] Error: Sensor still waking up.")
                
            default:
                break
            }
            
            _appStatus.sensorStatus = .NeedsUserToConnect
            updateAppStatusMessage()
        }
        
        updateIdleTimer()
        
        return result
    }
    
    func startStructureSensorStreaming() {
        
        if !isStructureConnectedAndCharged() {
            return
        }
        
        // Tell the driver to start streaming.
        if _useColorCamera {
            
            if _options.useHardwareRegisteredDepth {
                
                // We are using the color camera, so let's make sure the depth gets synchronized with it.
                // If we use registered depth, we also need to specify a fixed lens position value for the color camera.
                do {
                    //	NSLog("RegisteredDepth320x240")
                    try _sensorController.startStreamingWithOptions([kSTStreamConfigKey: STStreamConfig.RegisteredDepth320x240.rawValue, kSTFrameSyncConfigKey:  STFrameSyncConfig.DepthAndRgb.rawValue, kSTColorCameraFixedLensPositionKey: _options.lensPosition])
                } catch let error as NSError {
                    
                    NSLog("Error during streaming start: %s", error.localizedDescription)
                    
                    return
                }
            } else {
                // We are using the color camera, so let's make sure the depth gets synchronized with it.
                do {
                    //NSLog("Depth320x240")
                    try _sensorController.startStreamingWithOptions([kSTStreamConfigKey: STStreamConfig.Depth320x240.rawValue, kSTFrameSyncConfigKey: STFrameSyncConfig.DepthAndRgb.rawValue])
                } catch let error as NSError {
                    
                    NSLog("Error during streaming start: %s", error.localizedDescription)
                    
                    return
                }
            }
            
            startColorCamera()
            
        } else {
            
            do {
                //NSLog("Depth320x240")
                try _sensorController.startStreamingWithOptions([kSTStreamConfigKey: STStreamConfig.Depth320x240.rawValue, kSTFrameSyncConfigKey: STFrameSyncConfig.Off.rawValue])
                
            } catch let error as NSError {
                
                NSLog("Error during streaming start: %s", error.localizedDescription)
                
                return
            }
        }
        
        NSLog("[Structure] Streaming started.")
        
        // Notify and initialize streaming dependent objects.
        onStructureSensorStartedStreaming()
    }
    
    func onStructureSensorStartedStreaming() {
        
        // The Calibrator app will be updated to support future iPads, and additional attachment brackets will be released as well.
        let deviceIsLikelySupportedByCalibratorApp = (UIDevice.currentDevice().userInterfaceIdiom == .Pad)
        
        let calibrationType = _sensorController.calibrationType()
        // Only present the option to switch over to the Calibrator app if the sensor doesn't already have a device specific
        // calibration and the app knows how to calibrate this iOS device.
        if calibrationType != .DeviceSpecific && deviceIsLikelySupportedByCalibratorApp {
            
            calibrationOverlay.alpha = 1
            calibrationOverlay.hidden = false
        }
        else {
            calibrationOverlay.alpha = 0
            calibrationOverlay.hidden = true
        }
        
        if !_slamState.initialized {
            setupSLAM()
        }
    }
    
    func sensorDidOutputSynchronizedDepthFrame(depthFrame: STDepthFrame!, colorFrame: STColorFrame!) {
        
        if _slamState.initialized {
            
            processDepthFrame(depthFrame, colorFrame: colorFrame)
            // Scene rendering is triggered by new frames to avoid rendering the same view several times.
            renderSceneForDepthFrame(depthFrame, colorFrame: colorFrame)
        }
    }
    
    func sensorDidOutputDepthFrame(depthFrame: STDepthFrame) {
        
        if _slamState.initialized {
            
            processDepthFrame(depthFrame, colorFrame: nil)
            
            // Scene rendering is triggered by new frames to avoid rendering the same view several times.
            renderSceneForDepthFrame(depthFrame, colorFrame: nil)        }
    }
}


