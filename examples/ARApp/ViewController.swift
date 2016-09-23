//
//  ViewController.swift
//  ARToolKitWithSwift
//
//  Created by 藤澤研究室 on 2016/07/11.
//  Copyright © 2016年 藤澤研究室. All rights reserved.
// sa2taka

import UIKit
import QuartzCore

class ViewController: UIViewController, CameraVideoTookPictureDelegate, EAGLViewTookSnapshotDelegate {
    var runLoopInterval: Int = 0
    var runLoopTimePrevious: NSTimeInterval = 0.0
    var videoPaused: Bool

    // Video acquisition
    var gVid: UnsafeMutablePointer<AR2VideoParamT> = UnsafeMutablePointer<AR2VideoParamT>.alloc(1)

    // Marker detection.
    var gARHandle: UnsafeMutablePointer<ARHandle>
    var gARPattHandle: UnsafeMutablePointer<ARPattHandle>
    var gCallCountMarkerDetect: Int = 0

    // Transformation matrix retrieval.
    var gAR3DHandle: UnsafeMutablePointer<AR3DHandle>
    var gPatt_width: ARdouble = 0.0
    var gPatt_trans34: [[ARdouble]] = []
    var gPatt_found: Int32 = 0
    var gPatt_id: Int32 = 0
    var useContPoseEstimation: Bool
    var gCparamLT: UnsafeMutablePointer<ARParamLT>

    private(set) var glView: ARView? = ARView()
    private(set) var arglContextSettings: ARGL_CONTEXT_SETTINGS_REF
    private(set) var running: Bool
    var paused: Bool
    var markersHaveWhiteBorders: Bool

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
        self.view = irisView
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
        self.start()
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
                self.stop()
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
                self.stopRunLoop()
                self.startRunLoop()
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
        let vconf: UnsafePointer<CChar>
        gVid = ar2VideoOpenAsync(&vconf, startCallback, self)
        if (gVid != nil) {
            print("Error: Unable to open connection to camera.\n")
            self.stop()
            return
        }
    }

    var startCallback = { (userData: UnsafeMutablePointer<Void>) in
        let vc: ViewController =

    }

    func start2() {
        // Find the size of the window.
        var xsize, ysize: UnsafeMutablePointer<Int32>
        if (ar2VideoGetSize(gVid, xsize, ysize) < 0) {
            print("Error: ar2VideoGetSize.")
            self.stop()
            return
        }

        // Get the format in which the camera is returning pixels.
        var pixFormat = ar2VideoGetPixelFormat(gVid)
        if (pixFormat == AR_PIXEL_FORMAT_INVALID) {
            print("Error: Camera is using unsupported pixel format.")
            self.stop()
            return
        }

        // Work out if the front camera is being used. If it is, flip the viewing frustum for
        // 3D drawing.
        var flipV: Bool = false
        var frontCamera: UnsafeMutablePointer<Int32>
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
        var cparam: UnsafeMutablePointer<ARParam>
        if (ar2VideoGetCParam(gVid, cparam) < 0) {
            var cparam_name: String? = "Data2/camera_para.dat"
            print("Unable to automatically determine camera parameters. Using default.\n")
            if (arParamLoadFromBuffer(cparam_name!, 1, cparam) < 0) {
                print("Error: Unable to load parameter file %s for camera.\n", cparam_name)
                self.stop()
                return
            }
        }
        if (cparam[0].xsize != xsize[0] || cparam[0].ysize != ysize[0]) {
            arParamChangeSize(cparam, xsize[0], ysize[0], cparam)
        }

        gCparamLT = arParamLTCreate(cparam, AR_PARAM_LT_DEFAULT_OFFSET)
        if (gCparamLT == nil) {
            print("Error: arParamLTCreate.\n")
            self.stop()
            return
        }

        // AR init.
        gARHandle = arCreateHandle(gCparamLT)
        if (gARHandle == nil) {
            print("Error: arCreateHandle.\n")
            self.stop()
            return
        }
        if (arSetPixelFormat(gARHandle, pixFormat) < 0) {
            print("Error: arSetPixelFormat.\n")
            self.stop()
            return
        }
        gAR3DHandle = ar3DCreateHandle(&gCparamLT[0].param)
        if (gAR3DHandle == nil) {
            print("Error: ar3DCreateHandle.\n")
            self.stop()
            return
        }

        // libARvideo on iPhone uses an underlying class called CameraVideo. Here, we
        // access the instance of this class to get/set some special types of information.
        var cameraVideo: CameraVideo? = ar2VideoGetNativeVideoInstanceiPhone(gVid[0].device.iPhone)
        if (cameraVideo == nil) {
            print("Error: Unable to set up AR camera: missing CameraVideo instance.\n")
            self.stop()
            return
        }

        // The camera will be started by -startRunLoop.
        cameraVideo.cameraVideoTookPicture(self, userData: nil)

        // Other ARToolKit setup.
        arSetMarkerExtractionMode(gARHandle, AR_USE_TRACKING_HISTORY_V2)
        //arSetMarkerExtractionMode(gARHandle, AR_NOUSE_TRACKING_HISTORY)
        //arSetLabelingThreshMode(gARHandle, AR_LABELING_THRESH_MODE_MANUAL) // Uncomment to use  manual thresholding.

        // Allocate the OpenGL view.
        glView = ARView.alloc().initWithFrame(UIScreen.mainScreen().bounds(pixelFormat(kEAGLColorFormatRGBA8), depthFormat(kEAGLDepth16), withStencil(false), preserveBackbuffer(false)).autorelease) // Don't retain it, as it will be retained when added to self.view.
        glView?.arViewController = self
        self.view(addSubview(glView))

        // Create the OpenGL projection from the calibrated camera parameters.
        // If flipV is set, flip.
        var frustum: [GLfloat]
        arglCameraFrustumRHf(&gCparamLT[0].param, VIEW_DISTANCE_MIN, VIEW_DISTANCE_MAX, frustum)
        glView.setCameraLens(frustum)
        glView?.contentFlipV = flipV

        // Set up content positioning.
        glView?.contentScaleMode = ARViewContentScaleModeFill
        glView?.contentAlignMode = ARViewContentAlignModeCenter
        glView!.contentWidth = gARHandle[0].xsize
        glView!.contentHeight = gARHandle[0].ysize
        var isBackingTallerThanWide: Bool = (glView!.surfaceSize.height > glView!.surfaceSize.width)
        if (glView?.contentWidth > glView!.contentHeight) {
            glView?.contentRotate90 = isBackingTallerThanWide
        }
        else {
            glView?.contentRotate90 = !isBackingTallerThanWide
        }

        // Setup ARGL to draw the background video.
        arglContextSettings = arglSetupForCurrentContext(&gCparamLT[0].param, pixFormat)

        arglSetRotate90(arglContextSettings, (glView!.contentWidth > glView!.contentHeight ? isBackingTallerThanWide : !isBackingTallerThanWide))
        if (flipV) {
            arglSetFlipV(arglContextSettings, 1/*Objc: 1, Swift: true*/)
        }
        var width: UnsafeMutablePointer<Int32>
        var height: UnsafeMutablePointer<Int32>
        ar2VideoGetBufferSize(gVid, width, height)
        arglPixelBufferSizeSet(arglContextSettings, width[0], height[0])
        gARPattHandle = arPattCreateHandle()
        // Prepare ARToolKit to load patterns.
        if gARPattHandle == nil {
            print("Error: arPattCreateHandle.\n")
            self.stop()
            return
        }
        arPattAttach(gARHandle, gARPattHandle)

        // Load marker(s).
        // Loading only 1 pattern in this example.
        var patt_name: String = "Data2/hiro.patt"
        gPatt_id = arPattLoad(gARPattHandle, patt_name)
        if gPatt_id < 0 {
            print("Error loading pattern file \(patt_name).\n")
            self.stop()
            return
        }
        gPatt_width = 40.0
        gPatt_found = 0

        // For FPS statistics.
        arUtilTimerReset()
        gCallCountMarkerDetect = 0

        //Create our runloop timer
        self.setRunLoopInterval(2) // Target 30 fps on a 60 fps device.
        self.startRunLoop()
    }
    
    func cameraVideoTookPicture(sender: AnyObject, userData data: AnyObject) {
        let buffer: UnsafeMutablePointer<AR2VideoBufferT> = ar2VideoGetImage(gVid)
        if (buffer != nil) {
            self.processFrame(buffer)
        }
    }
    
    func processFrame(buffer: UnsafeMutablePointer<AR2VideoBufferT>) {
        var err : ARdouble
        var j : Int32 = 0
        var k : Int32 = -1
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
            
            while (j < gARHandle.memory.marker_num) {
                if (gARHandle.markerInfo[j].id == gPatt_id) {
                    if (k == -1)
                    {
                        k = j // First marker detected.
                    }
                    else if (gARHandle.markerInfo[j].cf > gARHandle.markerInfo[k].cf)
                    {
                        k = j // Higher confidence marker detected.
                    }
                }
                j += 1
            }
            
            if (k != -1)
            {
                // Get the transformation between the marker and the real camera into gPatt_trans.
                if ((gPatt_found != 0) && useContPoseEstimation)
                {
                    err = arGetTransMatSquareCont(gAR3DHandle, &(gARHandle.markerInfo[k]), gPatt_trans34, gPatt_width, gPatt_trans34)
                }
                else
                {
                    err = arGetTransMatSquare(gAR3DHandle, &(gARHandle.markerInfo[k]), gPatt_width, gPatt_trans34)
                }
                var modelview : [Float] = []
                gPatt_found = 1
                glView.setCameraPose(modelview)
            } else {
                gPatt_found = 0
                glView.setCameraPose(nil)
            }
            
            // Get current time (units = seconds).
            var runLoopTimeNow:
                runLoopTimeNow = CFAbsoluteTimeGetCurrent()
            glView.updateWithTimeDelta(runLoopTimeNow - runLoopTimePrevious)
            
            // The display has changed.
            glView!.drawView(self)
            
            // Save timestamp for next loop.
            runLoopTimePrevious = runLoopTimeNow
        }
    }
    
    @IBAction func stop() {
        self.stopRunLoop()
        
        if (arglContextSettings != nil) {
            arglCleanup(arglContextSettings)
            arglContextSettings = nil
        }
        glView?.removeFromSuperview()
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
        self.stop()
        super.viewWillDisappear(animated)
    }

    /* メモリの解放を行いたい
     deinit {
     super.dealloc() // そもそもUIViewControllerはメモリ解放が必要なのか?
     }
     */

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
        glView?.tookSnapshotDelegate(self)
        glView?.takeSnapshot()
    }

    //- (void) tookSnapshot:(UIImage *)image forView:(EAGLView *)view;
    // Here you can choose what to do with the image.
    // We will save it to the iOS camera roll.
    func tookSnapshot(snapshot: UnsafeMutablePointer<UIImage>, forView view:UnsafeMutablePointer<EAGLView>) {
        // First though, unset ourselves as delegate.
        glView?.tookSnapshotDelegate(nil)

        // Write image to camera roll.
        UIImageWriteToSavedPhotosAlbum(snapshot[0], self, #selector(ViewController.image), nil)
    }

    // Let the user know that the image was saved by playing a shutter sound,
    // or if there was an error, put up an alert.
    func image(image:UnsafeMutablePointer<UIImage>, didFinishSavingWithError error:UnsafeMutablePointer<NSError>, contextInfo: UnsafeMutablePointer<Void>) {
        if (error != nil) {
            var shutterSound: SystemSoundID
            AudioServicesCreateSystemSoundID(NSBundle.mainBundle().URLForResource("slr_camera_shutter", withExtension: "wav") as! CFURLRef, &shutterSound)
            AudioServicesPlaySystemSound(shutterSound)
        } else {
            var titleString: String? = "Error saving screenshot"
            var messageString: String? = error.debugDescription
            var moreString: String = (error[0].localizedFailureReason != nil) ? error[0].localizedFailureReason! : NSLocalizedString("Please try again.", comment: "")
            messageString = NSString.init(format: "%@. %@", messageString!, moreString) as String
            //var alertView: UIAlertView? = UIAlertView.alloc(initWithTitle(titleString!), message(messageString), delegate(self), cancelButtonTitle("OK"), otherButtonTitles(nil))
            var alertView: UIAlertView? = UIAlertView.init(title: titleString!, message: messageString!, delegate: self, cancelButtonTitle: self, otherButtonTitles: nil)
            alertView?.show()
            //alertView?.release()
        }
    }
}
