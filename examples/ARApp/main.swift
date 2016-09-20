//
//  main.swift
//  ARToolKit5iOS
//
//  Created by 藤澤研究室 on 2016/09/14.
//
//

import Foundation
import UIKit

exit(UIApplicationMain(CommandLine.argc,
                       UnsafeMutableRawPointer(CommandLine.unsafeArgv).bindMemory(to: UnsafeMutablePointer<Int8>.self, capacity: Int(CommandLine.argc)),
                       nil,
                       NSStringFromClass(ARAppDelegate.self)))
