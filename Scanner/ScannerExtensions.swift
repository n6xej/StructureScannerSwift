//
//	Extensions for Swift port of the Structure SDK sample app "Scanner".
//	Copyright © 2016 Christopher Worley. All rights reserved.
//
//  ScannerExtensions.swift
//
//  Ported by Christopher Worley on 8/20/16.
//


extension NSTimer {
	class func schedule(delay: NSTimeInterval, handler: NSTimer! -> Void) -> NSTimer {
		let fireDate = delay + CFAbsoluteTimeGetCurrent()
		let timer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, fireDate, 0, 0, 0, handler)
		CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, kCFRunLoopCommonModes)
		return timer
	}
}

public extension Float {
	public static let epsilon: Float = 1e-8
	func nearlyEqual(b: Float) -> Bool {
		return abs(self - b) < Float.epsilon
	}
}

public class FileMgr: NSObject {
    
    private var rootPath: String!
    private var basePath: NSString!
    
    class var sharedInstance: FileMgr {
        struct Static {
            static var onceToken: dispatch_once_t = 0
            static var instance: FileMgr? = nil
        }
        dispatch_once(&Static.onceToken) {
            Static.instance = FileMgr.init()
        }
        return Static.instance!
    }

    private override init() {
        super.init()
        let paths = NSFileManager.defaultManager().URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask)
        self.rootPath = paths[0].path!
        self.basePath = (self.rootPath as NSString)
    }
    
    private func mksubdir( subpath: String) -> Bool {
        
        let fullPath = self.full(subpath)
        
        if !self.exists(fullPath) {
            
            do {
                try NSFileManager.defaultManager().createDirectoryAtPath(fullPath, withIntermediateDirectories: true, attributes: nil)
                return true
            }
            catch {
                return false
            }
        }
        
        return true
    }
    
    func useSubpath( subPath: String) {
        
        mksubdir(subPath)
        self.basePath = (rootPath as NSString).stringByAppendingPathComponent(subPath)
    }
    
    func root() -> NSString {
        
        return self.rootPath as NSString
    }
    
    func full( name: String) -> String {
        
        return self.basePath.stringByAppendingPathComponent(name)
    }
    
    func del( name: String) {
        
        let name = self.basePath.stringByAppendingPathComponent(name)
        
        do {
            try NSFileManager.defaultManager().removeItemAtPath(name)
        }
        catch {
            print("Error deleting \(name) \(error)")
        }
    }
    
    func getData( name: String) -> NSData? {
        
        let fullPathFile = self.basePath.stringByAppendingPathComponent(name)
        
        if self.exists(fullPathFile) {
            
            if let data = NSData(contentsOfFile: fullPathFile) {
                return data
            }
            
            print("Error reading data")
            return nil
        }
        
        print("Error no file \(name)")
        return nil
    }
    
    func saveData( name: String, data: NSData) -> NSData? {
        
        let fullPathFile = self.basePath.stringByAppendingPathComponent(name)
        
        if self.exists(fullPathFile) {
            self.del(fullPathFile)
        }
        
        do {
            try  data.writeToFile( fullPathFile, options:NSDataWritingOptions.AtomicWrite )
            return data
        }
        catch {
            print("Error writing file \(error)")
            return nil
        }
    }
    
    func saveMesh( name: String, data: STMesh) -> NSData? {
        
        let options: [NSObject : AnyObject] = [ kSTMeshWriteOptionFileFormatKey : STMeshWriteOptionFileFormat.ObjFileZip.rawValue]
        
        let fullPathFile = self.basePath.stringByAppendingPathComponent(name)
        
        if self.exists(fullPathFile) {
            self.del(fullPathFile)
        }
        
        do {
            try data.writeToFile(fullPathFile, options: options)
            
            if let zipData = NSData(contentsOfFile: fullPathFile) {
                return zipData
            }
            print("Error reading mesh")
            return nil
        }
        catch {
            print("Error writing mesh \(error)")
            return nil
        }
    }
    
    func filepath( subdir: String, name: String) -> String? {
        
        let fullPathFile = self.full(subdir)
        
        if !self.exists(fullPathFile) {
            
            do {
                try NSFileManager.defaultManager().createDirectoryAtPath(fullPathFile, withIntermediateDirectories: true, attributes: nil)
                
                return (fullPathFile as NSString).stringByAppendingPathComponent(name)
            }
            catch {
                return nil
            }
        }
        
        return (fullPathFile as NSString).stringByAppendingPathComponent(name)
        
    }
    
    func exists( name: String) -> Bool {
        
        let fullPath = self.basePath.stringByAppendingPathComponent(name)
        
        return NSFileManager.defaultManager().fileExistsAtPath(fullPath)
    }
}

