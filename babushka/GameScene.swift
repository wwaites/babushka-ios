//
//  GameScene.swift
//  babushka - telepresence robot controller for iOS devices
//
//  Created by William Waites on 29/10/2017.
//  Copyright © 2017 Groovy Network Services Ltd. All rights reserved.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

import SpriteKit
import GameplayKit
import CoreMotion

class GameScene: SKScene {
    
    // user interface elements
    private var leftMotorLabel : SKLabelNode?
    private var rightMotorLabel : SKLabelNode?
    private var runningLabel : SKLabelNode?
    private var accelLabel : SKLabelNode?
    private var statusLabel : SKLabelNode?

    // used to get accelerometer data
    private var motionManager : CMMotionManager?

    // flag to emit motor control packets only if running
    private var running : Bool = false
    
    // signed values for the speed of each motor.
    // greater than zero means forwards, less than
    // zero means reverse
    private var leftMotor : Int8 = 0
    private var rightMotor : Int8 = 0
    
    // network socket and paraphenalia
    private var sock : Int32 = 0
    private var src_addr = sockaddr_in()
    private var dst_addr = sockaddr_in()
    private var host = "192.168.88.2"
    private var port : Int16 = 9003
    
    // put status on the screen, usually if something has
    // gone wrong
    func status(text: String) {
        if let label = self.statusLabel {
            label.text = text
        }
    }

    // stop the robot
    func stop() {
        // explicitly tell the motor to stop, in case
        setMotor(left: 0, right: 0)
        emitMotorControlPacket()

        running = false
        if let label = self.runningLabel {
            //label.run(SKAction.init(named: "Pulse")!, withKey: "fadeInOut")
            label.run(SKAction.fadeOut(withDuration: 0.0))
            label.text = "stopped"
            label.run(SKAction.fadeIn(withDuration: 1.0))
        }
    }
    
    // start the robot
    func start() {
        running = true
        if let label = self.runningLabel {
            label.run(SKAction.fadeOut(withDuration: 0.0))
            label.text = "running"
            label.run(SKAction.fadeIn(withDuration: 1.0))
        }
    }
    
    // set the motor speed values, greater than zero is forwards
    // and less than zero is backwards
    func setMotor(left: Int8, right: Int8) {
        if let label = self.leftMotorLabel {
            label.text = String(left)
        }
        if let label = self.rightMotorLabel {
            label.text = String(right)
        }
        leftMotor = left
        rightMotor = right
    }

    // update the motor control data given the accelerometer values
    func updateAccel(x: Double, y: Double) {
        let s = String(format: "X: %.05f", x) + String(format: "\tY: %.05f", y)
        if let label = self.accelLabel {
            label.text = s
        }
        
        // scale x and y so we don't have to turn the
        let xx = x / 0.5
        let yy = y
        var left = (xx + yy) * 127
        var right = (xx - yy) * 127
        
        // clip so that we don't exceed the range of uint
        if left > 127 { left = 127 }
        if left < -127 { left = -127 }
        if right > 127 { right = 127 }
        if right < -127 { right = -127 }

        setMotor(left: Int8(left), right: Int8(right))
    }
    
    // send motor control data to the network
    func emitMotorControlPacket() {
        if sock < 0 {
            return
        }

        // figure out which opcode to use for each
        // motor, left forward and reverse are 1 and 0
        // respectively...
        var lop: UInt8
        var left : UInt8
        if leftMotor > 0 {
            lop = 1
            left = UInt8(leftMotor)
        } else {
            lop = 0
            left = UInt8(-1 * leftMotor)
        }
        
        // ...and right are 4 and 5. for reverse we need
        // to change the sign to be positive
        var rop : UInt8
        var right : UInt8
        if rightMotor > 0 {
            rop = 4
            right = UInt8(rightMotor)
        } else {
            rop = 5
            right = UInt8(-1 * rightMotor)
        }

        // the data buffer to send, starts with a 1
        let buf : [UInt8] = [1, lop, left, rop, right]
        
        // finally send it
        let slen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bytesSent = withUnsafeMutablePointer(to: &dst_addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                sendto(sock, buf, buf.count, 0, UnsafeMutablePointer<sockaddr>($0), slen)
            }
        }
        if bytesSent != buf.count {
            status(text: String(format: "error sending packet (%d) errno %s", bytesSent, strerror(errno)))
        }
    }
    
    // what it sounds like, set up the network socket
    func setupSocket() {
        if sock >= 0 {
            close(sock)
        }
        
        sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        if sock < 0 {
            status(text: String(format: "error creating socket: %s", strerror(errno)))
            return
        }
        
        // configure the client's source address
        src_addr.sin_family = sa_family_t(AF_INET)
        src_addr.sin_port = in_port_t(port.bigEndian)
        src_addr.sin_addr.s_addr = in_addr_t(INADDR_ANY)
    
        // configure destination address
        dst_addr.sin_family = sa_family_t(AF_INET)
        dst_addr.sin_port = in_port_t(port.bigEndian)

        var buffer: [Int8] = Array(host.utf8CString)
        // convert address into 32 bit number
        if (inet_aton(&buffer, &dst_addr.sin_addr) == 0) {
            status(text: String(format: "error parsing destination address (%s): %s", host, strerror(errno)))
            close(sock)
            sock = -1
            return
        }
        
        // bind the socket
        let ret = withUnsafeMutablePointer(to: &src_addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(sock, UnsafeMutablePointer<sockaddr>($0), socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if ret == -1 {
            status(text: String(format: "error binding socket: %s", strerror(errno)))
            close(sock)
            sock = -1
            return
        }
    }
    
    // this strangely named function gets called when this "scene" is created.
    // it is the entry point
    override func didMove(to view: SKView) {
        // Get labels node from scene and store them for use later
        self.leftMotorLabel = self.childNode(withName: "//leftMotorLabel") as? SKLabelNode
        self.rightMotorLabel = self.childNode(withName: "//rightMotorLabel") as? SKLabelNode
        self.runningLabel = self.childNode(withName: "//runningLabel") as? SKLabelNode
        self.accelLabel = self.childNode(withName: "//accelLabel") as? SKLabelNode
        self.statusLabel = self.childNode(withName: "//statusLabel") as? SKLabelNode
        
        // start accelerometer going
        motionManager = CMMotionManager()
        motionManager?.startAccelerometerUpdates()
        
        // set up the netowrk socket
        setupSocket()

        // make sure we are stopped
        stop()
   
        // every so often send a packet out on the network
        let wait = SKAction.wait(forDuration: 0.1)
        let emit = SKAction.run {
            if self.running {
                self.emitMotorControlPacket()
            }
        }
        run(SKAction.repeatForever(SKAction.sequence([wait, emit])))
    }
    
    // start the robot if a finger is pressed
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        start()
    }
    
    // stop the robot if a finger is released
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        stop()
    }
    
    // also stop if the touch event has been cancelled for some reason
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        stop()
    }
    
    override func update(_ currentTime: TimeInterval) {
        // Called before each frame is rendered. maybe this should only be done
        // in our timer? dunno...
        if let ad = motionManager?.accelerometerData {
            updateAccel(x: ad.acceleration.x, y: ad.acceleration.y)
        }
    }
}
