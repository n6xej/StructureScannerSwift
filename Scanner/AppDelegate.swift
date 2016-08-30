//
//	This file is a Swift port of the Structure SDK sample app "Scanner".
//	Copyright © 2016 Occipital, Inc. All rights reserved.
//	http://structure.io
//
//  AppDelegate.swift
//
//  Ported by Christopher Worley on 8/20/16.
//


@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    var STdebugger: Bool = false
    
    func preventApplicationFromStartingInTheBackgroundWhenTheStructureSensorIsPlugged() {
        // Sadly, iOS 9.2+ introduced unexpected behavior: every time a Structure Sensor is plugged in to iOS, iOS will launch all Structure-related apps in the background.
        // The apps will not be visible to the user.
        // This can cause problems since Structure SDK apps typically ask the user for permission to use the camera when launched.
        // This leads to the user's first experience with a Structure SDK app being:
        //     1.  Download Structure SDK apps from App Store.
        //     2.  Plug in Structure Sensor to iPad.
        //     3.  Get bombarded with "X app wants to use the Camera" notifications from every installed Structure SDK app.
        // Each app has to deal with this problem in its own way.
        // In the Structure SDK, sample apps peacefully exit without causing a crash report.
        // This also has other benefits, such as not using memory.
        // Note that Structure SDK does not support connecting to Structure Sensor if the app is in the background.
        
        if UIApplication.sharedApplication().applicationState == .Background {
            let displayName = NSBundle.mainBundle().objectForInfoDictionaryKey("CFBundleDisplayName")
            print("iOS launched \(displayName) in the background. This app is not designed to be launched in the background, so it will exit peacefully.")
            
            exit(0)
        }
    }

	func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject : AnyObject]?) -> Bool {

        // Override point for customization after application launch.
        preventApplicationFromStartingInTheBackgroundWhenTheStructureSensorIsPlugged()
		

        if (STdebugger)
        {
            // STWirelessLog is very helpful for debugging while your Structure Sensor is plugged in.
            // See SDK documentation for how to start a listener on your computer.
            
            var error: NSError? = nil
			let remoteLogHost = "192.168.1.1"
            
            STWirelessLog.broadcastLogsToWirelessConsoleAtAddress(remoteLogHost, usingPort: 49999, error: &error)
            
            if error != nil {
                let errmsg = error!.localizedDescription
                NSLog("Oh no! Can't start wireless log: %@", errmsg)
            }
        }

        return true
    }

    func applicationWillResignActive(application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(application: UIApplication) {
        // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }

}

