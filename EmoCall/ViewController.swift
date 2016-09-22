//
//  ViewController.swift
//  VideoSampleCaptureRender
//
//  Created by Piyush Tank on 3/10/16.
//  Copyright © 2016 Twilio. All rights reserved.
//

import UIKit
import KeenClient
import TwilioCommon

class ViewController: UIViewController, UITextFieldDelegate {
    
    // Twilio Access Token - Generate a demo Access Token at https://www.twilio.com/user/account/video/dev-tools/testing-tools
    let twilioAccessToken = "TWILIO_ACCESS_TOKEN"
    
     // Storyboard's outlets
    @IBOutlet weak var spinner: UIActivityIndicatorView!
    @IBOutlet weak var statusMessage: UILabel!
    @IBOutlet weak var inviteeTextField: UITextField!
    @IBOutlet weak var disconnectButton: UIButton!

    @IBOutlet weak var valenceField: UILabel!
    @IBOutlet weak var emojiField: UILabel!

    // Key Twilio ConversationsClient SDK objects
    var client: TwilioConversationsClient?
    var localMedia: TWCLocalMedia?
    var camera: TWCCameraCapturer?
    var conversation: TWCConversation?
    var outgoingInvite: TWCOutgoingInvite?
    var remoteVideoRenderer: TWCVideoViewRenderer?
    var affectivaVideoRenderer: AffectivaRenderer?

    // Video containers used to display local camera track and remote Participant's camera track
    var localVideoContainer: UIView?
    var remoteVideoContainer: UIView?
    
    // If set to true, the remote video renderer (of type TWCVideoViewRenderer) will not automatically handle rotation of the remote party's video track. Instead, you should respond to the 'renderer:orientiationDidChange:' method in your TWCVideoViewRendererDelegate.
    let applicationHandlesRemoteVideoFrameRotation = false
    var valenceValue : Float = 0 {
        didSet {
            print("Valence is \(valenceValue)")
        }
    }
    var emojiChar : String = ""
    
    // ConversationsClient status - used to dynamically update our UI
    enum ConversationsClientStatus: Int {
        case none = 0
        case failedToListen
        case listening
        case connecting
        case connected
    }
    
    // Default status to None
    var clientStatus: ConversationsClientStatus = .none
    
    func updateClientStatus(_ status: ConversationsClientStatus, animated: Bool) {
        self.clientStatus = status
        
        // Update UI elements when the ConversationsClient status changes
        switch self.clientStatus {
        case .none:
            break
        case .failedToListen:
            spinner.stopAnimating()
            self.statusMessage.isHidden = false
            self.statusMessage.text = "Failure while attempting to listen for Conversation Invites."
            self.view.bringSubview(toFront: self.statusMessage)
            self.localVideoContainer?.isHidden = true
            self.emojiField.isHidden = true
            self.valenceField.isHidden = true
        case .listening:
            spinner.stopAnimating()
            self.disconnectButton.isHidden = true
            self.inviteeTextField.isHidden = false
            self.localVideoContainer?.isHidden = false
            self.statusMessage.isHidden = true
            self.emojiField.isHidden = true
            self.valenceField.isHidden = true
            KeenClient.shared().upload(finishedBlock: nil);
        case .connecting:
            self.spinner.startAnimating()
            self.inviteeTextField.isHidden = true
            self.localVideoContainer?.isHidden = false
            self.emojiField.isHidden = true
            self.valenceField.isHidden = true
        case .connected:
            self.spinner.stopAnimating()
            self.inviteeTextField.isHidden = true
            self.view.endEditing(true)
            self.disconnectButton.isHidden = false
            self.localVideoContainer?.isHidden = false
            self.emojiField.isHidden = false
            self.valenceField.isHidden = false
        }
        // Update UI Layout, optionally animated
        self.view.setNeedsLayout()
        if animated {
            UIView.animate(withDuration: 0.2, animations: { () -> Void in
                self.view.layoutIfNeeded()
            }) 
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // self.view is loaded from Main.storyboard, however the local and remote video containers are created programmatically
        
        // Video containers
        self.remoteVideoContainer = UIView(frame: self.view.frame)
        self.view.addSubview(self.remoteVideoContainer!)
        self.remoteVideoContainer!.backgroundColor = UIColor.black
        self.localVideoContainer = UIView(frame: self.view.frame)
        self.view.addSubview(self.localVideoContainer!)
        self.localVideoContainer!.backgroundColor = UIColor.black
        self.localVideoContainer!.isHidden = true
        
        // Entry text field for the identity to invite to a Conversation (the invitee)
        inviteeTextField.alpha = 0.9
        inviteeTextField.isHidden = true
        inviteeTextField.autocorrectionType = .no
        inviteeTextField.returnKeyType = .send
        self.view.bringSubview(toFront: self.inviteeTextField)
        self.view.bringSubview(toFront: self.emojiField)
        self.view.bringSubview(toFront: self.valenceField)
        self.emojiField.isHidden = true
        self.valenceField.isHidden = true
        self.inviteeTextField.delegate = self
        
        // Spinner - shown when attempting to listen for Invites and when sending an Invite
        self.view.addSubview(spinner)
        spinner.startAnimating()
        self.view.bringSubview(toFront: self.spinner)
        
        // Status message - used to display errors
        statusMessage.isHidden = true
        
        // Disconnect button
        self.view.bringSubview(toFront: self.disconnectButton)
        self.disconnectButton.isHidden = true
        
        // Setup the local media
        self.setupLocalMedia()
        
        // Start listening for Invites
        TwilioConversationsClient.setLogLevel(.warning)
        self.listenForInvites()
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        
        // Layout video containers
        self.layoutLocalVideoContainer()
        self.layoutRemoteVideoContainer()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override var prefersStatusBarHidden : Bool {
        return true
    }
    
    // Hide the keyboard whenever a touch is detected on this view
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        self.view.endEditing(true)
    }
    
    // Disconnect button
    @IBAction func disconnectButtonClicked (_ sender : AnyObject) {
        if conversation != nil {
            conversation?.disconnect()
        }
    }
    
    func layoutLocalVideoContainer() {
        var rect:CGRect! = CGRect.zero
        
        // If connected to a Conversation, display a small representaiton of the local video track in the bottom right corner
        if clientStatus == .connected {
            rect!.size = UIDeviceOrientationIsLandscape(UIDevice.current.orientation) ? CGSize(width: 160, height: 90) : CGSize(width: 90, height: 160)
            rect!.origin = CGPoint(x: self.view.frame.width - rect!.width - 10, y: self.view.frame.height - rect!.height - 10)
        } else {
            // If not yet connected to a Conversation (e.g. Camera preview), display the local video feed as full screen
            rect = self.view.frame
        }
        self.localVideoContainer!.frame = rect
        self.localVideoContainer?.alpha = clientStatus == .connecting ? 0.25 : 1.0
    }
    
    func layoutRemoteVideoContainer() {
        if clientStatus == .connected {
            // When connected to a Conversation, display the remote video feed as full screen.
            if applicationHandlesRemoteVideoFrameRotation {
                // This block demonstrates how to manually handle remote video track rotation
                let rotated = TWCVideoOrientationIsRotated(self.remoteVideoRenderer!.videoFrameOrientation)
                let transform = TWCVideoOrientationMakeTransform(self.remoteVideoRenderer!.videoFrameOrientation)
                self.remoteVideoRenderer!.view.transform = transform
                self.remoteVideoContainer!.bounds = (rotated == true) ?
                    CGRect(x: 0, y: 0, width: self.view.frame.height, height: self.view.frame.width) :
                    CGRect(x: 0, y: 0, width: self.view.frame.width,  height: self.view.frame.height)
            } else {
                // In this block, because the TWCVideoViewRenderer is handling remote video track rotation automatically, we simply set the remote video container size to full screen
                self.remoteVideoContainer!.bounds = CGRect(x: 0,y: 0,width: self.view.frame.width, height: self.view.frame.height)
            }
            self.remoteVideoContainer!.center = self.view.center
            self.remoteVideoRenderer!.view.bounds = self.remoteVideoContainer!.frame
        } else {
            // If not connected to a Conversation, there is no remote video to display
            self.remoteVideoContainer!.frame = CGRect.zero
        }
    }
    
    func listenForInvites() {
        assert(self.twilioAccessToken != "TWILIO_ACCESS_TOKEN", "Set the value of the placeholder property 'twilioAccessToken' to a valid Twilio Access Token.")
        let accessManager = TwilioAccessManager(token: self.twilioAccessToken, delegate:nil);
        self.client = TwilioConversationsClient(accessManager: accessManager!, delegate: self);
        self.client!.listen()
    }
    
    func setupLocalMedia() {
        // LocalMedia represents the collection of tracks that we are sending to other Participants from our ConversationsClient
        self.localMedia = TWCLocalMedia()
        // Currently, the microphone is automatically captured and an audio track is added to our LocalMedia. However, we should manually create a video track using the device's camera and the TWCCameraCapturer class
        if Platform.isSimulator == false {
            createCapturer()
            setupLocalPreview()
        }
    }
    
    func createCapturer() {
        self.camera = TWCCameraCapturer(delegate: self, source: .frontCamera)
        let videoCaptureConstraints = self.videoCaptureConstraints()
        let videoTrack = TWCLocalVideoTrack(capturer: self.camera!, constraints: videoCaptureConstraints)
        if self.localMedia!.add(videoTrack) == false {
            print("Error: Failed to create a video track using the local camera.")
        }
    }
    
    func videoCaptureConstraints () -> TWCVideoConstraints {
        /* Video constraints provide a mechanism to capture a video track using a preferred frame size and/or frame rate.
         
         Here, we set the captured frame size to 960x540. Check TWCCameraCapturer.h for other valid video constraints values.
         
         960x540 video will fill modern iPhone screens. However, older 32-bit devices (A5, A6 based) will have trouble capturing, and encoding video at HD quality. For these devices we constrain the capturer to produce 480x360 video at 15fps. */
        
        if (Platform.isLowPerformanceDevice) {
            return TWCVideoConstraints(maxSize: TWCVideoConstraintsSize480x360, minSize: TWCVideoConstraintsSize480x360, maxFrameRate: 15, minFrameRate: 15)
        } else {
            return TWCVideoConstraints(maxSize: TWCVideoConstraintsSize960x540, minSize: TWCVideoConstraintsSize960x540, maxFrameRate: 0, minFrameRate: 0)
        }
    }
    
    func setupLocalPreview() {
        self.camera!.startPreview()
        
        // Preview our local camera track in the local video container
        self.localVideoContainer!.addSubview((self.camera!.previewView)!)
        self.camera!.previewView!.frame = self.localVideoContainer!.bounds
    }
    
    func destroyLocalMedia() {
        self.camera?.previewView?.removeFromSuperview()
        self.camera = nil
        self.localMedia = nil
    }
    
    func resetClientStatus() {
        // Reset the local media
        destroyLocalMedia()
        setupLocalMedia()
        
        // Reset the client ui status
        updateClientStatus(self.client!.listening ? .listening : .failedToListen, animated: true)
    }
    
    // Respond to "Send" button on keyboard
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.view.endEditing(true)
        inviteParticipant(textField.text!)
        return false
    }
    
    func inviteParticipant(_ inviteeIdentity: String) {
        if inviteeIdentity.isEmpty == false {
            self.outgoingInvite =
                self.client?.invite(toConversation: inviteeIdentity, localMedia:self.localMedia!) { conversation, err in
                    self.outgoingInviteCompletionHandler(conversation, err: err)
            }
            self.updateClientStatus(.connecting, animated: false)
        }
    }
    
    func outgoingInviteCompletionHandler(_ conversation: TWCConversation?, err: Error?) {
        if err == nil {
            // The invitee accepted our Invite
            self.conversation = conversation
            self.conversation?.delegate = self
        } else {
            // The invitee rejected our Invite or the Invite was not acknowledged
            let alertController = UIAlertController(title: "Oops!", message: "Unable to connect to the remote party.", preferredStyle: .alert)
            let OKAction = UIAlertAction(title: "OK", style: .default) { (action) in  }
            alertController.addAction(OKAction)
            self.present(alertController, animated: true) { }
            
            // Destroy the old local media and set up new local media.
            self.resetClientStatus()
        }
    }
    
    func showEmoji(_ emoji : String) -> Void {
        self.emojiField.text = emoji
    }


    func showValence(_ valence : Float) -> Void {
        if valence >= 0 {
            self.valenceField.text = "👍"
            self.valenceField.textColor = UIColor.white
            self.valenceField.backgroundColor = UIColor.init(red: 0.0, green: 1.0, blue: 0.0, alpha: CGFloat(valence) / 100.0 + 0.4)
        } else {
            self.valenceField.text = "👎"
            self.valenceField.textColor = UIColor.white
            self.valenceField.backgroundColor = UIColor.init(red: 1.0, green: 0.0, blue: 0.0, alpha: CGFloat(valence) / 100.0 + 0.4)
        }
        if self.conversation?.sid != nil && valence != 0.0 {
            
            let event = ["conversation_sid": String((self.conversation?.sid!)!)!, "conversation_valence": NSNumber(value: valence)] as [String : Any]
            do {
                try KeenClient.shared().addEvent(event, toEventCollection: "affdex_valence_events")
            } catch _ {
            };
        }
    }
}

// MARK: TwilioConversationsClientDelegate
extension ViewController: TwilioConversationsClientDelegate {
    func conversationsClient(_ conversationsClient: TwilioConversationsClient,
                             didFailToStartListeningWithError error: Error) {
        
        // Do not interrupt the on going conversation UI. Client status will
        // changed to .FailedToListen when conversation ends.
        if (conversation == nil) {
            self.updateClientStatus(.failedToListen, animated: false)
        }
    }
    
    func conversationsClientDidStartListening(forInvites conversationsClient: TwilioConversationsClient) {
        // Successfully listening for Invites
        
        // Do not interrupt the on going conversation UI. Client status will
        // changed to .Listening when conversation ends.
        if (conversation == nil) {
            self.updateClientStatus(.listening, animated: true)
        }
    }
    
    func conversationsClientDidStopListening(forInvites conversationsClient: TwilioConversationsClient, error: Error?) {
        // Do not interrupt the on going conversation UI. Client status will
        // changed to .Listening when conversation ends.
        if (conversation == nil) {
            self.updateClientStatus(.failedToListen, animated: true)
        }
    }
    
    // Automatically accept any incoming Invite
    func conversationsClient(_ conversationsClient: TwilioConversationsClient,
                             didReceive invite: TWCIncomingInvite) {
        let alertController = UIAlertController(title: "Incoming Invite!", message: "Invite from \(invite.from)", preferredStyle: .alert)
        let acceptAction = UIAlertAction(title: "Accept", style: .default) { (action) in
            // Accept the incoming Invite with pre-configured LocalMedia
            self.updateClientStatus(.connecting, animated: false)
            invite.accept(with: self.localMedia!, completion: { (conversation, err) -> Void in
                if err == nil {
                    self.conversation = conversation
                    conversation!.delegate = self
                } else {
                    print("Error: Unable to connect to accepted Conversation")
                    
                    // Destroy the old local media and set up new local media.
                    self.resetClientStatus()
                }
            })
        }
        alertController.addAction(acceptAction)
        let rejectAction = UIAlertAction(title: "Reject", style: .cancel) { (action) in
            invite.reject()
        }
        alertController.addAction(rejectAction)
        self.present(alertController, animated: true) { }
    }
}

// MARK: TWCConversationDelegate
extension ViewController: TWCConversationDelegate {
    func conversation(_ conversation: TWCConversation, didConnect participant: TWCParticipant) {
        // Remote Participant connected
        participant.delegate = self
    }
    
    func conversationEnded(_ conversation: TWCConversation) {
        self.conversation = nil
        self.resetClientStatus()
    }
}

// MARK: TWCParticipantDelegate
extension ViewController: TWCParticipantDelegate {
    func participant(_ participant: TWCParticipant, addedVideoTrack videoTrack: TWCVideoTrack) {
        // Remote Participant added a video track. Render it onto the remote video track container.
        self.remoteVideoRenderer = TWCVideoViewRenderer(delegate: self)
        self.affectivaVideoRenderer = AffectivaRenderer(updateClosure: { (valence: Float, emoji: String) -> Void in
            self.showEmoji(emoji)
            self.showValence(valence)
        } )
        videoTrack.addRenderer(self.remoteVideoRenderer!)

        videoTrack.addRenderer(self.affectivaVideoRenderer!)
        self.remoteVideoRenderer!.view.bounds = self.remoteVideoContainer!.frame
        
        self.remoteVideoContainer!.addSubview(self.remoteVideoRenderer!.view)
        
        // Animate the remote video track onto the screen.
        self.updateClientStatus(.connected, animated: true)
    }
    
    func participant(_ participant: TWCParticipant, removedVideoTrack videoTrack: TWCVideoTrack) {
        // Remote Participant removed their video track
        self.remoteVideoRenderer!.view.removeFromSuperview()
    }
}

// MARK: TWCLocalMediaDelegate
extension ViewController: TWCLocalMediaDelegate {
    func localMedia(_ media: TWCLocalMedia, didFailToAdd videoTrack: TWCVideoTrack, error: Error) {
        // Called when there is a failure attempting to add a local video track to LocalMedia. In this application, it is likely to be caused when capturing a video track from the device camera using invalid video constraints.
        print("Error: failed to add a local video track to LocalMedia.")
    }
}

// MARK: TWCCameraCapturerDelegate
extension ViewController : TWCCameraCapturerDelegate {
    func cameraCapturerPreviewDidStart(_ capturer: TWCCameraCapturer) {
        if (self.client!.listening) {
            self.localVideoContainer!.isHidden = false
        }
    }
    
    func cameraCapturer(_ capturer: TWCCameraCapturer, didStartWith source: TWCVideoCaptureSource) {
        self.statusMessage.isHidden = true
    }
    
    func cameraCapturer(_ capturer: TWCCameraCapturer, didStopRunningWithError error: Error) {
        // Failed to capture video from the local device camera
        self.statusMessage.isHidden = false
        self.statusMessage.text = "Error: failed to capture video from your device's camera."
    }
    
    /* The local video track representing your captured camera will be automatically disabled (paused) when there is an interruption - for example, when the app is backgrounded.
     If you do not wish to pause the local video track when the TWCCameraCapturer is interrupted, you should also implement the 'cameraCapturerWasInterrupted' delegate method. */
}

// MARK: TWCVideoViewRendererDelegate
extension ViewController: TWCVideoViewRendererDelegate {
    func rendererDidReceiveVideoData(_ renderer: TWCVideoViewRenderer) {
        // Called when the first frame of video is received on the remote Participant's video track
        self.view.setNeedsLayout()
    }
    
    func renderer(_ renderer: TWCVideoViewRenderer, dimensionsDidChange dimensions: CMVideoDimensions) {
        // Called when the remote Participant's video track changes dimensions
        self.view.setNeedsLayout()
    }
    
    func renderer(_ renderer: TWCVideoViewRenderer, orientationDidChange orientation: TWCVideoOrientation) {
        // Called when the remote Participant's video track is rotated. Only ever called if 'rendererShouldRotateContent' returns true.
        self.view.setNeedsLayout()
        UIView.animate(withDuration: 0.2, animations: { () -> Void in
            self.view.layoutIfNeeded()
        }) 
    }
    
    func rendererShouldRotateContent(_ renderer: TWCVideoViewRenderer) -> Bool {
        return !applicationHandlesRemoteVideoFrameRotation
    }
}
  
