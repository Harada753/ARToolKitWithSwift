//
//  AppDelegate.swift
//  ARToolKitBySwift
//
//  Created by 藤澤研究室 on 2016/07/11.
//  Copyright © 2016年 藤澤研究室. All rights reserved.
//

import UIKit

@UIApplicationMain // main.mの代わりになる
class ARAppDelegate: UIResponder, UIApplicationDelegate {
        
    @IBOutlet var window: UIWindow!
    @IBOutlet var viewController: ARViewController!

    // アプリが起動した時の処理
    @objc internal func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
        // Override point for customization after application launch.
        
        // Set working directory so that camera parameters, models etc. can be loaded using relative paths.
        arUtilChangeToResourcesDirectory(AR_UTIL_RESOURCES_DIRECTORY_BEHAVIOR(rawValue: AR_UTIL_RESOURCES_DIRECTORY_BEHAVIOR_BEST.rawValue), nil)
        
        
        self.window.rootViewController = self.viewController
        window.makeKeyAndVisible()

        return true
    }

    // アプリがバックグラウンドになった時の処理
    func applicationWillResignActive(application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
        //viewController.paused = true
    }

    // アプリがバックグラウンドになった時の処理
    func applicationDidEnterBackground(application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    // アプリがバックグラウンドから戻ってきた時の処理
    func applicationWillEnterForeground(application: UIApplication) {
        // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
    }

    // アプリがバックグラウンドから戻ってきた時の処理
    func applicationDidBecomeActive(application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
        //viewController.paused = false
    }

    // アプリが終了する特の処理
    func applicationWillTerminate(application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }
    
    // メモリの開放
    deinit {
        self.viewController = nil
        self.window = nil
    }

}

