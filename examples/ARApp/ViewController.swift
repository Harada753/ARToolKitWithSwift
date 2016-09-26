//
//  ViewController.swift
//  ARToolKitWithSwift
//
//  Created by 藤澤研究室 on 2016/07/11.
//  Copyright © 2016年 藤澤研究室. All rights reserved.
//

import UIKit
import QuartzCore

class ARViewController: UIViewController, UIAlertViewDelegate, CameraVideoTookPictureDelegate, EAGLViewTookSnapshotDelegate {
    var runLoopInterval: Int = 0
    var runLoopTimePrevious: NSTimeInterval = 0.0
    var videoPaused: Bool = false
    
    // Video acquisition
    var gVid: UnsafeMutablePointer<AR2VideoParamT> = nil
    
    // Marker detection.
    var gARHandle: UnsafeMutablePointer<ARHandle> = nil
    var gARPattHandle: UnsafeMutablePointer<ARPattHandle> = nil
    var gCallCountMarkerDetect: Int = 0
    
    // Transformation matrix retrieval.
    var gAR3DHandle: UnsafeMutablePointer<AR3DHandle> = nil
    var gPatt_width: ARdouble = 0.0
    var gPatt_trans34: UnsafeMutablePointer<(ARdouble, ARdouble, ARdouble, ARdouble)> = nil
    var gPatt_found: Int32 = 0
    var gPatt_id: Int32 = 0
    var useContPoseEstimation: Bool = false
    var gCparamLT: UnsafeMutablePointer<ARParamLT> = nil
    
    private(set) var glView: UnsafeMutablePointer<ARView> = nil
    private(set) var arglContextSettings: ARGL_CONTEXT_SETTINGS_REF = nil
    private(set) var running: Bool = false
    var paused: Bool = false
    var markersHaveWhiteBorders: Bool = false
    
    let VIEW_DISTANCE_MIN: Float = 5.0
    let VIEW_DISTANCE_MAX: Float = 2000.0
    
    // ロード画面の描画
    override func loadView() {
        // This will be overlaid with the actual AR view.
        var irisImage : String? = nil
        if (UIDevice.currentDevice().userInterfaceIdiom == .Pad) {
            irisImage = "Iris-iPad.png"
        } else { // UIDevice.current.userInterfaceIdiom == .Phone
            let result = UIScreen.mainScreen().bounds.size
            if (result.height == 568) {
                irisImage = "Iris-568h.png" // iPhone 5, iPod touch 5th Gen, etc.
            } else { // result.height == 480
                irisImage = "Iris.png"
            }
        }
        let myImage: UIImage = UIImage(named: irisImage!)!
        let irisView = UIImageView(image: myImage)
        irisView.userInteractionEnabled = true // タッチの検知を行う
        view = irisView
    }
    
    // Viewが初めて呼び出されるとき一回呼ばれる
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        // 変数の初期化
        gCallCountMarkerDetect = 0
        useContPoseEstimation = false
        running = false
        videoPaused = false
        runLoopTimePrevious = CFAbsoluteTimeGetCurrent()
    }
    
    // 画面が表示された直後に実行される
    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
        start()
    }
    
    // On iOS 6.0 and later, we must explicitly report which orientations this view controller supports.
    func supportedInterfaceOrientationsBySwift() -> UIInterfaceOrientationMask { // change func name
        return UIInterfaceOrientationMask.Portrait
    }
    
    func startRunLoop() {
        if (!running) {
            // After starting the video, new frames will invoke cameraVideoTookPicture:userData:.
            if (ar2VideoCapStart(gVid) != 0) {
                print("Error: Unable to begin camera data capture.\n")
                stop()
                return
            }
            running = true
        }
    }
    
    func stopRunLoop() {
        if (running) {
            ar2VideoCapStop(gVid)
            running = false
        }
    }
    
    private func setRunLoopInterval(interval: Int) {
        if (interval >= 1) {
            runLoopInterval = interval
            if (running) {
                stopRunLoop()
                startRunLoop()
            }
        }
    }
    
    func isPaused() -> Bool {
        if (!running) {
            return(false)
        }
        return (videoPaused)
    }
    
    private func setPaused(paused: Bool) {
        if (!running) {
            return
        }
        if (videoPaused != paused) {
            if (paused) {
                ar2VideoCapStop(gVid)
            }
            else {
                ar2VideoCapStart(gVid)
            }
            videoPaused = paused
        }
    }
    
    @IBAction func start() {
        let vconf: UnsafePointer<Int8> = nil
        let ref: UnsafeMutablePointer<Void> = unsafeBitCast(self, UnsafeMutablePointer<Void>.self)
        gVid = ar2VideoOpenAsync(vconf, startCallback, ref)
        if (gVid != nil) {
            print("Error: Unable to open connection to camera.\n")
            stop()
            return
        }
    }
    /*
    func startCallback(userData: UnsafeMutablePointer<Void>){
        let vc: ARViewController = (userData.memory as? ARViewController)!
        vc.start2()
    }
 */
    
    let startCallback: @convention(c) (UnsafeMutablePointer<Void>) -> Void = {
        (userData) in
        let vc: ARViewController = (userData.memory as? ARViewController)!
        vc.start2()
    }
    
    func start2() {
        // Find the size of the window.
        let xsize: UnsafeMutablePointer<Int32>
        let ysize: UnsafeMutablePointer<Int32>
        if (ar2VideoGetSize(gVid, xsize, ysize) < 0) {
            print("Error: ar2VideoGetSize.")
            stop()
            return
        }
        
        // Get the format in which the camera is returning pixels.
        let pixFormat = ar2VideoGetPixelFormat(gVid)
        if (pixFormat == AR_PIXEL_FORMAT_INVALID) {
            print("Error: Camera is using unsupported pixel format.")
            stop()
            return
        }
        
        // Work out if the front camera is being used. If it is, flip the viewing frustum for
        // 3D drawing.
        var flipV: Bool = false
        let frontCamera: UnsafeMutablePointer<Int32>
        if (ar2VideoGetParami(gVid, Int32(AR_VIDEO_PARAM_IOS_CAMERA_POSITION), frontCamera) >= 0) {
            
            if (frontCamera[0] == AR_VIDEO_IOS_CAMERA_POSITION_FRONT.rawValue) {
                flipV = true
            }
        }
        
        // Tell arVideo what the typical focal distance will be. Note that this does NOT
        // change the actual focus, but on devices with non-fixed focus, it lets arVideo
        // choose a better set of camera parameters.
        ar2VideoSetParami(gVid, Int32(AR_VIDEO_PARAM_IOS_FOCUS), Int32(AR_VIDEO_IOS_FOCUS_0_3M.rawValue))
        // Default is 0.3 metres. See <AR/sys/videoiPhone.h> for allowable values.
        
        // Load the camera parameters, resize for the window and init.
        let cparam: UnsafeMutablePointer<ARParam>
        if (ar2VideoGetCParam(gVid, cparam) < 0) {
            let cparam_name: String? = "Data2/camera_para.dat"
            print("Unable to automatically determine camera parameters. Using default.\n")
            if (arParamLoadFromBuffer(cparam_name!, 1, cparam) < 0) {
                print("Error: Unable to load parameter file %s for camera.\n", cparam_name)
                stop()
                return
            }
        }
        if (cparam[0].xsize != xsize[0] || cparam[0].ysize != ysize[0]) {
            arParamChangeSize(cparam, xsize[0], ysize[0], cparam)
        }
        
        gCparamLT = arParamLTCreate(cparam, AR_PARAM_LT_DEFAULT_OFFSET)
        if (gCparamLT == nil) {
            print("Error: arParamLTCreate.\n")
            stop()
            return
        }
        
        // AR init.
        gARHandle = arCreateHandle(gCparamLT)
        if (gARHandle == nil) {
            print("Error: arCreateHandle.\n")
            stop()
            return
        }
        if (arSetPixelFormat(gARHandle, pixFormat) < 0) {
            print("Error: arSetPixelFormat.\n")
            stop()
            return
        }
        gAR3DHandle = ar3DCreateHandle(&gCparamLT[0].param)
        if (gAR3DHandle == nil) {
            print("Error: ar3DCreateHandle.\n")
            stop()
            return
        }
        
        // libARvideo on iPhone uses an underlying class called CameraVideo. Here, we
        // access the instance of this class to get/set some special types of information.
        // let cameraVideo: CameraVideo? = ar2VideoGetNativeVideoInstanceiPhone(gVid[0].device.iPhone)
        let iphone = gVid[0].device.iPhone
        let cameraVideo: UnsafeMutablePointer<CameraVideo> = ar2VideoGetNativeVideoInstanceiPhone(iphone)
        if (cameraVideo == nil) {
            print("Error: Unable to set up AR camera: missing CameraVideo instance.\n")
            stop()
            return
        }
        
        // The camera will be started by -startRunLoop.
        cameraVideo[0].tookPictureDelegate = self
        cameraVideo[0].tookPictureDelegateUserData = nil
        
        // Other ARToolKit setup.
        arSetMarkerExtractionMode(gARHandle, AR_USE_TRACKING_HISTORY_V2)
        //arSetMarkerExtractionMode(gARHandle, AR_NOUSE_TRACKING_HISTORY)
        //arSetLabelingThreshMode(gARHandle, AR_LABELING_THRESH_MODE_MANUAL) // Uncomment to use  manual thresholding.
        
        // Allocate the OpenGL view.
        glView.memory = ARView.init(frame: UIScreen.mainScreen().bounds, pixelFormat: kEAGLColorFormatRGBA8, depthFormat: kEAGLDepth16, withStencil: false, preserveBackbuffer: false) // Don't retain it, as it will be retained when added to self.view.
        glView.memory.arViewController = self
        view.addSubview(glView.memory)
        
        // Create the OpenGL projection from the calibrated camera parameters.
        // If flipV is set, flip.
        let frustum: UnsafeMutablePointer<Float>
        arglCameraFrustumRHf(&gCparamLT[0].param, VIEW_DISTANCE_MIN, VIEW_DISTANCE_MAX, frustum)
        glView.memory.cameraLens = frustum
        glView.memory.contentFlipV = flipV
        
        // Set up content positioning.
        glView.memory.contentScaleMode = ARViewContentScaleModeFill
        glView.memory.contentAlignMode = ARViewContentAlignModeCenter
        glView.memory.contentWidth = gARHandle[0].xsize
        glView.memory.contentHeight = gARHandle[0].ysize
        let isBackingTallerThanWide: Bool = glView.memory.surfaceSize.height > glView.memory.surfaceSize.width
        if (glView.memory.contentWidth > glView.memory.contentHeight) {
            glView.memory.contentRotate90 = isBackingTallerThanWide
        }
        else {
            glView.memory.contentRotate90 = !isBackingTallerThanWide
        }
        
        // Setup ARGL to draw the background video.
        arglContextSettings = arglSetupForCurrentContext(&gCparamLT[0].param, pixFormat)
        
        let temp = { () -> Int8 in
            if (self.glView.memory.contentWidth > self.glView.memory.contentHeight) {
                return isBackingTallerThanWide ? 1 : 0
            }
            else {
                return isBackingTallerThanWide ? 0 : 1
            }
        }
        
        arglSetRotate90(arglContextSettings, temp())
        if (flipV) {
            arglSetFlipV(arglContextSettings, 1/*Objc: 1, Swift: true*/)
        }
        let width: UnsafeMutablePointer<Int32>
        let height: UnsafeMutablePointer<Int32>
        ar2VideoGetBufferSize(gVid, width, height)
        arglPixelBufferSizeSet(arglContextSettings, width[0], height[0])
        gARPattHandle = arPattCreateHandle()
        // Prepare ARToolKit to load patterns.
        if gARPattHandle == nil {
            print("Error: arPattCreateHandle.\n")
            stop()
            return
        }
        arPattAttach(gARHandle, gARPattHandle)
        
        // Load marker(s).
        // Loading only 1 pattern in this example.
        let patt_name: String = "Data2/hiro.patt"
        gPatt_id = arPattLoad(gARPattHandle, patt_name)
        if gPatt_id < 0 {
            print("Error loading pattern file \(patt_name).\n")
            stop()
            return
        }
        gPatt_width = 40.0
        gPatt_found = 0
        
        // For FPS statistics.
        arUtilTimerReset()
        gCallCountMarkerDetect = 0
        
        //Create our runloop timer
        setRunLoopInterval(2) // Target 30 fps on a 60 fps device.
        startRunLoop()
    }
    
    func cameraVideoTookPicture(sender: AnyObject, userData data: AnyObject) {
        let buffer: UnsafeMutablePointer<AR2VideoBufferT> = ar2VideoGetImage(gVid)
        if (buffer != nil) {
            processFrame(buffer)
        }
    }
    
    func processFrame(buffer: UnsafeMutablePointer<AR2VideoBufferT>) {
        var err : ARdouble
        var j : Int = 0
        var k : Int = -1
        if (buffer != nil)
        {
            let bufPlanes0 = buffer.memory.bufPlanes[0]
            let bufPlanes1 = buffer.memory.bufPlanes[1]
            // Upload the frame to OpenGL.
            if (buffer.memory.bufPlaneCount == 2)
            {
                arglPixelBufferDataUploadBiPlanar(arglContextSettings, bufPlanes0, bufPlanes1)
            }
            else
            {
                arglPixelBufferDataUploadBiPlanar(arglContextSettings, buffer.memory.buff, nil)
            }
            gCallCountMarkerDetect += 1 // Increment ARToolKit FPS counter.
            
            // Detect the markers in the video frame.
            if (arDetectMarker(gARHandle, buffer.memory.buff) < 0)
            {
                return
            }
            // Check through the marker_info array for highest confidence
            // visible marker matching our preferred pattern.
            while (j < Int(gARHandle.memory.marker_num)) {
                let markInfoId_j = withUnsafeMutablePointer(&gARHandle.memory.markerInfo.0) { (markerInfoPtr) -> Int32 in
                    return markerInfoPtr[0+j].id
                }
                let markInfoCf_j = withUnsafeMutablePointer(&gARHandle.memory.markerInfo.0) { (markerInfoPtr) -> ARdouble in
                    return markerInfoPtr[0+j].cf
                }
                let markInfoCf_k = withUnsafeMutablePointer(&gARHandle.memory.markerInfo.0) { (markerinfoPtr) -> ARdouble in
                    return markerinfoPtr[0+k].cf
                }
                if (markInfoId_j == gPatt_id) {
                    if (k == -1)
                    {
                        k = j // First marker detected.
                    }
                    else if (markInfoCf_j > markInfoCf_k)
                    {
                        k = j // Higher confidence marker detected.
                    }
                }
            }
            j += 1
        }
        
        if (k != -1)
        {
            var markInfo_k = withUnsafeMutablePointer(&gARHandle.memory.markerInfo.0) { (markerinfoPtr) -> ARMarkerInfo in
                return markerinfoPtr[0+k]
            }

            // Get the transformation between the marker and the real camera into gPatt_trans.
            if ((gPatt_found != 0) && useContPoseEstimation)
            {
                err = arGetTransMatSquareCont(gAR3DHandle, &markInfo_k, gPatt_trans34, gPatt_width, gPatt_trans34)
            }
            else
            {
                err = arGetTransMatSquare(gAR3DHandle, &markInfo_k, gPatt_width, gPatt_trans34)
            }
            let modelview: [Float] = []
            gPatt_found = 1
            glView.memory.cameraPose = UnsafeMutablePointer<Float>(modelview)
        } else {
            gPatt_found = 0
            glView.memory.cameraPose = nil
        }
        
        // Get current time (units = seconds).
        var runLoopTimeNow: NSTimeInterval
        runLoopTimeNow = CFAbsoluteTimeGetCurrent()
        glView.memory.updateWithTimeDelta(runLoopTimeNow - runLoopTimePrevious)
        
        // The display has changed.
        glView.memory.drawView(self)
        
        // Save timestamp for next loop.
        runLoopTimePrevious = runLoopTimeNow
    }
    
    @IBAction func stop() {
        stopRunLoop()
        
        if (arglContextSettings != nil) {
            arglCleanup(arglContextSettings)
            arglContextSettings = nil
        }
        glView.memory.removeFromSuperview()
        glView = nil
        
        if (gARHandle != nil){
            arPattDetach(gARHandle)
        }
        if (gARPattHandle != nil) {
            arPattDeleteHandle(gARPattHandle)
            gARHandle = nil
        }
        arParamLTFree(&gCparamLT)
        if (gVid != nil) {
            ar2VideoClose(gVid)
            gVid = nil
        }
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    // Viewが画面から消える直前に呼び出される
    override func viewWillDisappear(animated:Bool) {
        stop()
        super.viewWillDisappear(animated)
    }
    
    // 解放のタイミングで呼ばれる
    deinit {
        // super.dealloc()
    }
    
    // ARToolKit-specific methods.
    func markersHaveWhiteBordersBySwift() -> Bool { // change method name
        let mode: UnsafeMutablePointer<Int32>
        arGetLabelingMode(gARHandle, mode)
        return (mode[0] == AR_LABELING_WHITE_REGION)
    }
    
    func setMarkersHaveWhiteBordersBySwift(markersHaveWhiteBorders:Bool) {
        arSetLabelingMode(gARHandle, (markersHaveWhiteBorders ? AR_LABELING_WHITE_REGION : AR_LABELING_BLACK_REGION))
    }
    
    // Call this method to take a snapshot of the ARView.
    // Once the image is ready, tookSnapshot:forview: will be called.
    func takeSnapshot() {
        // We will need to wait for OpenGL rendering to complete.
        glView.memory.tookSnapshotDelegate = self
        glView.memory.takeSnapshot()
    }
    
    //- (void) tookSnapshot:(UIImage *)image forView:(EAGLView *)view;
    // Here you can choose what to do with the image.
    // We will save it to the iOS camera roll.
    func tookSnapshot(snapshot: UnsafeMutablePointer<UIImage>, forView view:UnsafeMutablePointer<EAGLView>) {
        // First though, unset ourselves as delegate.
        glView.memory.tookSnapshotDelegate = nil
        
        // Write image to camera roll.
        UIImageWriteToSavedPhotosAlbum(snapshot[0], self, #selector(ARViewController.image), nil)
    }
    
    // Let the user know that the image was saved by playing a shutter sound,
    // or if there was an error, put up an alert.
    func image(image:UnsafeMutablePointer<UIImage>, didFinishSavingWithError error:UnsafeMutablePointer<NSError>, contextInfo: UnsafeMutablePointer<Void>) {
        if (error != nil) {
            var shutterSound: SystemSoundID
            AudioServicesCreateSystemSoundID(NSBundle.mainBundle().URLForResource("slr_camera_shutter", withExtension: "wav") as! CFURLRef, &shutterSound)
            AudioServicesPlaySystemSound(shutterSound)
        } else {
            let titleString: String? = "Error saving screenshot"
            var messageString: String? = error.debugDescription
            let moreString: String = (error[0].localizedFailureReason != nil) ? error[0].localizedFailureReason! : NSLocalizedString("Please try again.", comment: "")
            messageString = NSString.init(format: "%@. %@", messageString!, moreString) as String
            // iOS 8.0以上
            if #available(iOS 8.0, *) {
                let alertView: UIAlertController = UIAlertController.init(title: titleString!, message: messageString!, preferredStyle: UIAlertControllerStyle.Alert)
                let cancelAction: UIAlertAction = UIAlertAction.init(title: "OK", style: UIAlertActionStyle.Cancel, handler: {
                    (action: UIAlertAction!) -> Void in
                    print("OK")
                })
                alertView.addAction(cancelAction)
                presentViewController(alertView, animated: true, completion: nil)
                // iOS 8.0未満
            } else {
                let alertView: UIAlertView = UIAlertView.init(title: titleString!, message: messageString!, delegate: self, cancelButtonTitle: "OK")
                alertView.show()
            }
        }
    }
    
}
