//
//  AffectivaRenderer.swift
//  VideoSampleCaptureRender
//
//  Created by Evan Cummack on 5/12/16.
//  Copyright © 2016 Twilio. All rights reserved.
//

import Foundation
import Affdex

extension UIImage {
    public func imageRotatedByDegrees(_ degrees: CGFloat, flip: Bool) -> UIImage {
        let degreesToRadians: (CGFloat) -> CGFloat = {
            return $0 / 180.0 * CGFloat(M_PI)
        }
        
        // calculate the size of the rotated view's containing box for our drawing space
        let rotatedViewBox = UIView(frame: CGRect(origin: CGPoint.zero, size: size))
        let t = CGAffineTransform.init(rotationAngle: degreesToRadians(degrees));
        rotatedViewBox.transform = t
        let rotatedSize = rotatedViewBox.frame.size
        
        // Create the bitmap context
        UIGraphicsBeginImageContext(rotatedSize)
        let bitmap = UIGraphicsGetCurrentContext()
        
        // Move the origin to the middle of the image so we will rotate and scale around the center.
        bitmap!.translateBy(x: rotatedSize.width / 2.0, y: rotatedSize.height / 2.0);
        
        //   // Rotate the image context
        bitmap!.rotate(by: degreesToRadians(degrees));
        
        // Now, draw the rotated/scaled image into the context
        var yFlip: CGFloat
        
        if(flip){
            yFlip = CGFloat(-1.0)
        } else {
            yFlip = CGFloat(1.0)
        }
        
        bitmap!.scaleBy(x: yFlip, y: -1.0)
        bitmap!.draw(self.cgImage!, in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return newImage!
    }
}

class AffectivaRenderer : NSObject, TWCVideoRenderer, AFDXDetectorDelegate {
    var detector : AFDXDetector?
    var baseTime : Date = Date()
    var lastProcessTime : Date = Date()
    let frameInterval : TimeInterval = 1.0 / 5.0
    let converter : I420Converter = I420Converter()
    var myUpdateClosure : ((Float, String) -> Void)?
    var orientation : TWCVideoOrientation? // track orientation for possible rotation
    
    // the initializer takes a closure
    init(updateClosure: @escaping (_ valence: Float, _ emoji: String) -> Void) {
        myUpdateClosure = updateClosure
    }
    
    func renderFrame(_ frame: TWCI420Frame) {
        // lazily initialize the detector
        if self.detector == nil {
            self.detector = AFDXDetector(delegate: self, discreteImages: false, maximumFaces: 1)
            self.detector?.licenseString = "AFFECTIVA_LICENSE"
            self.detector?.setDetectEmojis(true)
            self.detector?.valence = true
            assert(self.detector?.licenseString != "AFFECTIVA_LICENSE", "Set the value of the placeholder property 'licenseString' to a valid Affectiva license.")
            self.detector?.start()
        }
        
        // check if we're due for processing a frame
        if Date().timeIntervalSince(self.lastProcessTime) > frameInterval {
            // Affdex SDK requires UIImage here. Pass a frame every >= 100ms.
            // Convert I420 to UIImage and rotate if necessary
            var u : UIImage = converter.convertFrameVImageYUV(toUIImage: frame)
            
            // rotate the image if necessary
            switch orientation! {
            case TWCVideoOrientation.up:
                // do nothing
                break;
            case TWCVideoOrientation.left:
                // rotate UIImage to Up
                u = u.imageRotatedByDegrees(-90, flip: true)
                break;
            case TWCVideoOrientation.down:
                // rotate UIImage to Up
                u = u.imageRotatedByDegrees(-180, flip: true)
                break;
            case TWCVideoOrientation.right:
                // rotate UIImage to Up
                u = u.imageRotatedByDegrees(-270, flip: true)
                break;
            }

            // send the image to the Affdex emotion detector
            self.detector?.processImage(u, atTime: Date().timeIntervalSince(baseTime))
            
            // update our last process time variable
            self.lastProcessTime = Date()
        }
    }
    
    func updateVideoSize(_ videoSize: CMVideoDimensions, orientation: TWCVideoOrientation) {
        self.orientation = orientation
    }
    
    @objc func supportsVideoFrameOrientation() -> Bool {
        return true
    }
    
    // AFDXDetectorDelegate Methods
    func detector(_ detector: AFDXDetector!, hasResults faces: NSMutableDictionary!, for image: UIImage!, atTime time: TimeInterval) {
        if faces != nil {
            // this is a processed image -- go through face dictionary and pull out interesting values
            // the detector will only give us one face since that's all we asked for
            for face in faces.allValues as! [AFDXFace] {
                // call the closure with the valence and the emoji
                myUpdateClosure?(Float(face.emotions.valence), mapEmoji(face.emojis.dominantEmoji))
            }
        } else {
            // this is not a processed image -- we can ignore
        }
    }
    
    // this method maps an emoji code to an emoji character
    func mapEmoji(_ emojiCode : Emoji) -> String {
        switch emojiCode {
        case AFDX_EMOJI_RAGE:
            return "😡"
        case AFDX_EMOJI_WINK:
            return "😉"
        case AFDX_EMOJI_SMIRK:
            return "😏"
        case AFDX_EMOJI_SCREAM:
            return "😱"
        case AFDX_EMOJI_SMILEY:
            return "😀"
        case AFDX_EMOJI_FLUSHED:
            return "😳"
        case AFDX_EMOJI_KISSING:
            return "😗"
        case AFDX_EMOJI_STUCK_OUT_TONGUE:
            return "😛"
        case AFDX_EMOJI_STUCK_OUT_TONGUE_WINKING_EYE:
            return "😜"
        case AFDX_EMOJI_RELAXED:
            return "☺️"
        case AFDX_EMOJI_LAUGHING:
            return "😆"
        case AFDX_EMOJI_DISAPPOINTED:
            return "😞"
        default:
            return "😶"
        }
    }
}
