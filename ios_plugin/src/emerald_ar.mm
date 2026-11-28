// Emerald Online 8 Ball Pool AR (was Emerald Break) - walk-around AR on iPhone / iPad with Apple ARKit (GDExtension, Objective-C++).
//
// Same contract as the Android plugin (android_plugin/.../ArCoreSession.java), so the game's GDScript
// (src/ar/arcore_bridge.gd) needs no second code path. getState() layout (40 floats):
//   0 tracking (0 none, 1 limited/searching, 2 tracking)  1-3 camera position  4-7 camera rotation (x,y,z,w)
//   8 vertical field of view (degrees)  9 camera picture number  10-11 picture width, height
//   12-17 screen -> picture mapping (origin, x step, y step; normalised)  18 anchor (0 none, 1 limited, 2 tracking)
//   19-21 anchor position  22-25 anchor rotation  26 why tracking is limited (1 dark, 2 too fast, 3 no detail,
//   4 camera, 5 lost)  27 session (0 starting, 1 running, -1 failed: see getLastError)
//   28 the screen centre is on a found floor / table (1)  29-31 that point  32 found surfaces below the phone
//   33 height of the lowest one  34 screen orientation  35 distance to the point  36 failed camera opens (always 0
//   here)  37 waiting for the player to answer the camera permission question (1)  38-39 unused
//
// Everything runs on the main thread: Godot calls these methods from its main loop, ARKit's delegate calls
// arrive on the main queue, and the permission answer is sent there too. Positions are metres, Y up, the
// same world as ARKit's (gravity aligned); the camera pose is "display oriented" like ARCore's.

#import <ARKit/ARKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AuthenticationServices/AuthenticationServices.h>
#import <GameKit/GameKit.h>
#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <simd/simd.h>
#import <objc/message.h>

#include <sys/utsname.h>
#include <cfloat>
#include <cmath>
#include <cstring>

#include "emerald_ar.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>

static const int EAR_STATE_LEN = 40;

static godot::String ear_str(NSString *p_s) {
	return p_s ? godot::String::utf8(p_s.UTF8String) : godot::String();
}

// The orientation the game is shown in (it runs in landscape, either way up).
static UIInterfaceOrientation ear_orientation(UIInterfaceOrientation p_fallback) {
	if (![NSThread isMainThread]) {
		return p_fallback;
	}
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if ([scene isKindOfClass:[UIWindowScene class]]) {
			UIInterfaceOrientation o = ((UIWindowScene *)scene).interfaceOrientation;
			if (o != UIInterfaceOrientationUnknown) {
				return o;
			}
		}
	}
	return p_fallback;
}

static void ear_put_pose(float *p_s, int p_at, simd_float4x4 p_m) {
	simd_quatf q = simd_normalize(simd_quaternion(p_m));
	p_s[p_at + 0] = p_m.columns[3].x;
	p_s[p_at + 1] = p_m.columns[3].y;
	p_s[p_at + 2] = p_m.columns[3].z;
	p_s[p_at + 3] = q.vector.x;
	p_s[p_at + 4] = q.vector.y;
	p_s[p_at + 5] = q.vector.z;
	p_s[p_at + 6] = q.vector.w;
}

// ------------------------------------------------------------------------------------------ ARKit host
@interface EARHost : NSObject <ARSessionDelegate>
- (NSString *)availability;
- (BOOL)openAppSettings;
- (NSString *)lastError;
- (NSString *)info;
- (BOOL)startWidth:(int)w height:(int)h;
- (void)stop;
- (void)setViewWidth:(int)w height:(int)h;
- (void)fillState:(float *)out;
- (godot::PackedByteArray)imageY;
- (godot::PackedByteArray)imageUV;
- (BOOL)placeAnchor:(const float *)p;
- (void)clearAnchor;
@end

@implementation EARHost {
	ARSession *_session;
	ARAnchor *_anchor;
	int _gen;
	BOOL _running;
	int _status;
	BOOL _asking;
	NSString *_lastError;
	NSString *_formatInfo;
	int _viewW;
	int _viewH;
	UIInterfaceOrientation _orientation;
	NSTimeInterval _lastStamp;
	int _frameNo;
	int _imgW;
	int _imgH;
	float _state[EAR_STATE_LEN];
	godot::PackedByteArray _imgY;
	godot::PackedByteArray _imgUV;
}

- (instancetype)init {
	if ((self = [super init])) {
		_lastError = @"";
		_formatInfo = @"";
		_viewW = 1920;
		_viewH = 1080;
		_orientation = UIInterfaceOrientationLandscapeRight;
		_lastStamp = -1.0;
		memset(_state, 0, sizeof(_state));
	}
	return self;
}

- (NSString *)availability {
	return ARWorldTrackingConfiguration.isSupported ? @"installed" : @"unsupported";
}

- (BOOL)openAppSettings {
	dispatch_async(dispatch_get_main_queue(), ^{
		NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
		if (url) {
			[UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
		}
	});
	return YES;
}

- (NSString *)lastError {
	return _lastError ? _lastError : @"";
}

// One line of facts for the game's AR help panel.
- (NSString *)info {
	struct utsname u;
	uname(&u);
	NSString *perm = @"no";
	switch ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo]) {
		case AVAuthorizationStatusAuthorized:
			perm = @"yes";
			break;
		case AVAuthorizationStatusNotDetermined:
			perm = @"not asked yet";
			break;
		default:
			break;
	}
	NSMutableString *b = [NSMutableString stringWithFormat:@"%s, iOS %@, ARKit %@, camera permission %@", u.machine,
			UIDevice.currentDevice.systemVersion, ARWorldTrackingConfiguration.isSupported ? @"world tracking" : @"no world tracking", perm];
	if (_formatInfo.length > 0) {
		[b appendFormat:@", %@", _formatInfo];
	}
	return b;
}

- (BOOL)startWidth:(int)w height:(int)h {
	if (_running) {
		return YES;
	}
	[self dropSession];
	_viewW = w > 1 ? w : 1;
	_viewH = h > 1 ? h : 1;
	_lastError = @"";
	_formatInfo = @"";
	_status = 0;
	_asking = NO;
	_lastStamp = -1.0;
	_imgW = 0;
	_imgH = 0;
	memset(_state, 0, sizeof(_state));
	if (!ARWorldTrackingConfiguration.isSupported) {
		// reported through the state like any other failure, so the game shows the right reason
		_lastError = @"DeviceNotCompatible: ARKit world tracking isn't available on this device";
		_status = -1;
		return YES;
	}
	_running = YES;
	const int my_gen = ++_gen;
	switch ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo]) {
		case AVAuthorizationStatusAuthorized:
			[self runSession];
			break;
		case AVAuthorizationStatusNotDetermined: {
			// iOS asks the player now; the game waits (state[37] = 1) instead of timing out meanwhile
			_asking = YES;
			__weak EARHost *weak_self = self;
			[AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo
									 completionHandler:^(BOOL granted) {
										 dispatch_async(dispatch_get_main_queue(), ^{
											 [weak_self permissionAnswered:granted gen:my_gen];
										 });
									 }];
			break;
		}
		default:
			[self failPermission];
			break;
	}
	return YES;
}

- (void)permissionAnswered:(BOOL)granted gen:(int)gen {
	if (gen != _gen || !_running) {
		return; // stopped or restarted meanwhile
	}
	_asking = NO;
	if (granted) {
		[self runSession];
	} else {
		[self failPermission];
	}
}

- (void)failPermission {
	// "SecurityException" + "permission": the game's _classify() turns this into its camera-permission panel
	_lastError = @"SecurityException: camera permission denied (allow the camera for Emerald 8 Ball Pool in Settings)";
	_status = -1;
	_running = NO;
	_asking = NO;
}

- (void)runSession {
	ARWorldTrackingConfiguration *cfg = [ARWorldTrackingConfiguration new];
	cfg.planeDetection = ARPlaneDetectionHorizontal;
	cfg.lightEstimationEnabled = YES;
	cfg.worldAlignment = ARWorldAlignmentGravity;
	// A camera picture close to 1280x720, like on Android: sharp enough to fill the screen, cheap to copy.
	ARVideoFormat *best = nil;
	double best_score = DBL_MAX;
	for (ARVideoFormat *f in ARWorldTrackingConfiguration.supportedVideoFormats) {
		double px = f.imageResolution.width * f.imageResolution.height;
		double score = fabs(px - 1280.0 * 720.0) + (f.framesPerSecond >= 60 ? 0.0 : 1000.0);
		if (score < best_score) {
			best_score = score;
			best = f;
		}
	}
	if (best) {
		cfg.videoFormat = best;
	}
	ARVideoFormat *vf = cfg.videoFormat;
	_formatInfo = [NSString stringWithFormat:@"camera image %dx%d@%ld", (int)vf.imageResolution.width, (int)vf.imageResolution.height, (long)vf.framesPerSecond];
	_session = [ARSession new];
	_session.delegate = self;
	[_session runWithConfiguration:cfg options:ARSessionRunOptionResetTracking | ARSessionRunOptionRemoveExistingAnchors];
	_status = 1;
	NSLog(@"[EmeraldAR] session running: %@", [self info]);
}

- (void)dropSession {
	if (_session) {
		[_session pause];
		_session.delegate = nil;
		_session = nil;
	}
	_anchor = nil;
}

- (void)stop {
	_gen++;
	_running = NO;
	_asking = NO;
	_status = 0;
	[self dropSession];
	_state[0] = 0.0f;
	_state[18] = 0.0f;
	_state[27] = 0.0f;
	_state[36] = 0.0f;
	_state[37] = 0.0f;
}

- (void)setViewWidth:(int)w height:(int)h {
	_viewW = w > 1 ? w : 1;
	_viewH = h > 1 ? h : 1;
}

- (void)fillState:(float *)out {
	if (_running && _session) {
		[self update];
	}
	_state[27] = (float)_status;
	_state[36] = 0.0f;
	_state[37] = _asking ? 1.0f : 0.0f;
	memcpy(out, _state, sizeof(_state));
}

- (void)update {
	ARFrame *frame = _session.currentFrame;
	if (!frame) {
		return;
	}
	_orientation = ear_orientation(_orientation);
	ARCamera *cam = frame.camera;
	float *s = _state;

	float tracking = 0.0f;
	float failure = 0.0f;
	if (cam.trackingState == ARTrackingStateNormal) {
		tracking = 2.0f;
	} else if (cam.trackingState == ARTrackingStateLimited) {
		tracking = 1.0f;
		switch (cam.trackingStateReason) {
			case ARTrackingStateReasonExcessiveMotion:
				failure = 2.0f;
				break;
			case ARTrackingStateReasonInsufficientFeatures:
				// ARKit has no "too dark" reason: a dim room is the usual cause of too little detail
				failure = (frame.lightEstimate && frame.lightEstimate.ambientIntensity < 150.0) ? 1.0f : 3.0f;
				break;
			case ARTrackingStateReasonRelocalizing:
				failure = 5.0f;
				break;
			default:
				break; // initializing: still searching
		}
	}

	const CGSize view = CGSizeMake(_viewW, _viewH);
	// camera pose as the screen shows it (x right, y up, looking along -z), and the matching field of view
	simd_float4x4 pose = simd_inverse([cam viewMatrixForOrientation:_orientation]);
	simd_float4x4 proj = [cam projectionMatrixForOrientation:_orientation viewportSize:view zNear:0.05 zFar:100.0];
	const float fovy = (float)(2.0 * atan(1.0 / (double)proj.columns[1][1]) * 180.0 / M_PI);
	// screen (0..1, top left) -> camera picture (0..1, top left): rotation + crop
	CGAffineTransform to_image = CGAffineTransformInvert([frame displayTransformForOrientation:_orientation viewportSize:view]);
	CGPoint o = CGPointApplyAffineTransform(CGPointMake(0.0, 0.0), to_image);
	CGPoint px = CGPointApplyAffineTransform(CGPointMake(1.0, 0.0), to_image);
	CGPoint py = CGPointApplyAffineTransform(CGPointMake(0.0, 1.0), to_image);

	if (frame.timestamp != _lastStamp) {
		_lastStamp = frame.timestamp;
		[self copyImage:frame.capturedImage];
	}

	// the floor (or a table): a ray from the screen centre onto found horizontal surfaces below the phone
	float hit_ok = 0.0f, hx = 0.0f, hy = 0.0f, hz = 0.0f, hd = 0.0f, floor_y = 0.0f;
	int planes = 0;
	const simd_float3 cam_pos = cam.transform.columns[3].xyz;
	if (cam.trackingState == ARTrackingStateNormal) {
		CGPoint centre = CGPointApplyAffineTransform(CGPointMake(0.5, 0.5), to_image);
		ARRaycastQuery *query = [frame raycastQueryFromPoint:centre allowingTarget:ARRaycastTargetExistingPlaneGeometry alignment:ARRaycastTargetAlignmentHorizontal];
		for (ARRaycastResult *r in [_session raycast:query]) {
			if (![r.anchor isKindOfClass:[ARPlaneAnchor class]]) {
				continue;
			}
			const simd_float3 p = r.worldTransform.columns[3].xyz;
			if (p.y > cam_pos.y - 0.05f) {
				continue; // a ceiling, or something above the phone
			}
			hit_ok = 1.0f;
			hx = p.x;
			hy = p.y;
			hz = p.z;
			hd = simd_distance(p, cam_pos);
			break;
		}
		for (ARAnchor *a in frame.anchors) {
			if (![a isKindOfClass:[ARPlaneAnchor class]] || ((ARPlaneAnchor *)a).alignment != ARPlaneAnchorAlignmentHorizontal) {
				continue;
			}
			const float y = a.transform.columns[3].y;
			if (y > cam_pos.y - 0.05f) {
				continue;
			}
			if (planes == 0 || y < floor_y) {
				floor_y = y;
			}
			planes++;
		}
	}

	float anchor_tracking = 0.0f;
	if (_anchor) {
		for (ARAnchor *a in frame.anchors) {
			if ([a.identifier isEqual:_anchor.identifier]) {
				anchor_tracking = cam.trackingState == ARTrackingStateNormal ? 2.0f : 1.0f;
				ear_put_pose(s, 19, a.transform);
				break;
			}
		}
	}

	s[0] = tracking;
	if (cam.trackingState != ARTrackingStateNotAvailable) {
		ear_put_pose(s, 1, pose); // zeros until the first tracked frame, like ARCore
	}
	s[8] = fovy;
	s[9] = (float)_frameNo;
	s[10] = (float)_imgW;
	s[11] = (float)_imgH;
	s[12] = (float)o.x;
	s[13] = (float)o.y;
	s[14] = (float)(px.x - o.x);
	s[15] = (float)(px.y - o.y);
	s[16] = (float)(py.x - o.x);
	s[17] = (float)(py.y - o.y);
	s[18] = anchor_tracking;
	s[26] = failure;
	s[28] = hit_ok;
	s[29] = hx;
	s[30] = hy;
	s[31] = hz;
	s[32] = (float)planes;
	s[33] = floor_y;
	s[34] = (float)_orientation;
	s[35] = hd;
}

// 4:2:0 bi-planar full range (ARKit's capturedImage) -> Y plane (w*h) + interleaved CbCr (w/2*h/2*2), rows packed.
- (void)copyImage:(CVPixelBufferRef)pb {
	if (!pb || CVPixelBufferGetPlaneCount(pb) < 2) {
		return;
	}
	if (CVPixelBufferLockBaseAddress(pb, kCVPixelBufferLock_ReadOnly) != kCVReturnSuccess) {
		return;
	}
	const int w = (int)CVPixelBufferGetWidthOfPlane(pb, 0);
	const int h = (int)CVPixelBufferGetHeightOfPlane(pb, 0);
	const int cw = (int)CVPixelBufferGetWidthOfPlane(pb, 1);
	const int ch = (int)CVPixelBufferGetHeightOfPlane(pb, 1);
	const uint8_t *yb = (const uint8_t *)CVPixelBufferGetBaseAddressOfPlane(pb, 0);
	const uint8_t *cb = (const uint8_t *)CVPixelBufferGetBaseAddressOfPlane(pb, 1);
	const size_t y_row = CVPixelBufferGetBytesPerRowOfPlane(pb, 0);
	const size_t c_row = CVPixelBufferGetBytesPerRowOfPlane(pb, 1);
	if (yb && cb && w > 0 && h > 0 && cw == w / 2 && ch == h / 2) {
		const int64_t y_size = (int64_t)w * h;
		const int64_t c_size = (int64_t)cw * ch * 2;
		if (_imgY.size() != y_size) {
			_imgY.resize(y_size);
		}
		if (_imgUV.size() != c_size) {
			_imgUV.resize(c_size);
		}
		uint8_t *dy = _imgY.ptrw();
		uint8_t *dc = _imgUV.ptrw();
		for (int r = 0; r < h; r++) {
			memcpy(dy + (size_t)r * w, yb + (size_t)r * y_row, (size_t)w);
		}
		for (int r = 0; r < ch; r++) {
			memcpy(dc + (size_t)r * cw * 2, cb + (size_t)r * c_row, (size_t)cw * 2);
		}
		_imgW = w;
		_imgH = h;
		_frameNo++;
	}
	CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
}

- (godot::PackedByteArray)imageY {
	return _imgY;
}

- (godot::PackedByteArray)imageUV {
	return _imgUV;
}

// Pin the table: an ARKit anchor at that pose (x, y, z, qx, qy, qz, qw), kept in place as ARKit refines its map.
- (BOOL)placeAnchor:(const float *)p {
	if (!_session) {
		return NO;
	}
	if (_anchor) {
		[_session removeAnchor:_anchor];
		_anchor = nil;
	}
	simd_float4x4 m = simd_matrix4x4(simd_normalize(simd_quaternion(p[3], p[4], p[5], p[6])));
	m.columns[3] = simd_make_float4(p[0], p[1], p[2], 1.0f);
	_anchor = [[ARAnchor alloc] initWithName:@"table" transform:m];
	[_session addAnchor:_anchor];
	NSLog(@"[EmeraldAR] anchor placed");
	return YES;
}

- (void)clearAnchor {
	if (_anchor && _session) {
		[_session removeAnchor:_anchor];
	}
	_anchor = nil;
	_state[18] = 0.0f;
}

// ---------------------------------------------------------------- ARSessionDelegate
- (void)session:(ARSession *)session didFailWithError:(NSError *)error {
	if (session != _session) {
		return;
	}
	NSString *kind = @"";
	switch (error.code) {
		case ARErrorCodeCameraUnauthorized:
			kind = @"SecurityException: camera permission denied - ";
			break;
		case ARErrorCodeUnsupportedConfiguration:
			kind = @"DeviceNotCompatible: ";
			break;
		case ARErrorCodeSensorUnavailable:
		case ARErrorCodeSensorFailed:
			kind = @"CameraNotAvailable: ";
			break;
		default:
			break;
	}
	_lastError = [NSString stringWithFormat:@"%@ARKit error %ld: %@", kind, (long)error.code, error.localizedDescription];
	_status = -1;
	_running = NO;
	_asking = NO;
	[_session pause];
	NSLog(@"[EmeraldAR] %@", _lastError);
}

- (void)sessionWasInterrupted:(ARSession *)session {
	NSLog(@"[EmeraldAR] session interrupted (app in the background or camera taken)");
}

- (void)sessionInterruptionEnded:(ARSession *)session {
	NSLog(@"[EmeraldAR] session interruption ended: tracking resumes");
}

- (BOOL)sessionShouldAttemptRelocalization:(ARSession *)session {
	return YES;
}

@end

// ------------------------------------------------------------------------------------------ Godot side
// ------------------------------------------------------------------------------------------ sign-in (24 Nov 2026)
// Randy: "please do it the smoothe way with their sign in screens in app which doesnt need the browser to sign in".
//   Sign in with Apple: Apple's own sheet (Face ID / passcode) over the game; the identity token it hands back is
//     checked by the game's server (api.php auth_native: signed by Apple, for this app, with this sign-in's nonce).
//   Google / Facebook: their sign-in page in the iPhone's sign-in sheet (ASWebAuthenticationSession) over the game;
//     the server ends it on the game's own address (emeraldbreak://auth?r=ok), which closes the sheet.
// The game polls signInState(): "" idle, "busy", "token:TOKEN\nGIVEN_NAME", "cancel", "error:...", "tab",
// "tab_done:ok|error", "tab_closed" - the same words as the Android plugin (SignIn.java).
static UIWindow *ear_key_window() {
	UIWindow *any = nil;
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if ([scene isKindOfClass:[UIWindowScene class]]) {
			for (UIWindow *w in ((UIWindowScene *)scene).windows) {
				if (w.isKeyWindow) {
					return w;
				}
				if (!any) {
					any = w;
				}
			}
		}
	}
	return any;
}

@interface EARSignIn : NSObject <ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding,
		ASWebAuthenticationPresentationContextProviding>
@property(atomic, copy) NSString *state;
@property(atomic) NSInteger run;
@property(nonatomic, strong) ASAuthorizationController *apple;
@property(nonatomic, strong) ASWebAuthenticationSession *web;
@end

@implementation EARSignIn

- (instancetype)init {
	if ((self = [super init])) {
		_state = @"";
	}
	return self;
}

- (ASPresentationAnchor)presentationAnchorForAuthorizationController:(ASAuthorizationController *)controller {
	return ear_key_window();
}

- (ASPresentationAnchor)presentationAnchorForWebAuthenticationSession:(ASWebAuthenticationSession *)session {
	return ear_key_window();
}

- (void)finish:(NSInteger)mine state:(NSString *)s {
	if (mine == self.run) {
		self.state = s;
		NSLog(@"[EmeraldAR] sign-in: %@", [s hasPrefix:@"token:"] ? @"token" : s);
	}
}

- (BOOL)appleWithNonce:(NSString *)nonce {
	if (!nonce) {
		return NO;
	}
	NSInteger mine = ++self.run;
	self.state = @"busy";
	dispatch_async(dispatch_get_main_queue(), ^{
		if (mine != self.run) {
			return;
		}
		ASAuthorizationAppleIDRequest *r = [[ASAuthorizationAppleIDProvider new] createRequest];
		r.requestedScopes = @[ ASAuthorizationScopeFullName ];
		r.nonce = nonce;
		ASAuthorizationController *c = [[ASAuthorizationController alloc] initWithAuthorizationRequests:@[ r ]];
		c.delegate = self;
		c.presentationContextProvider = self;
		self.apple = c;
		[c performRequests];
	});
	return YES;
}

- (void)authorizationController:(ASAuthorizationController *)controller didCompleteWithAuthorization:(ASAuthorization *)authorization {
	if (controller != self.apple) {
		return;
	}
	self.apple = nil;
	NSString *s = @"error:no token";
	if ([authorization.credential isKindOfClass:[ASAuthorizationAppleIDCredential class]]) {
		ASAuthorizationAppleIDCredential *c = (ASAuthorizationAppleIDCredential *)authorization.credential;
		NSString *tok = c.identityToken ? [[NSString alloc] initWithData:c.identityToken encoding:NSUTF8StringEncoding] : nil;
		NSString *given = c.fullName.givenName ?: @"";      // (Apple gives the name the first time only)
		if (tok.length) {
			s = [NSString stringWithFormat:@"token:%@\n%@", tok, [given stringByReplacingOccurrencesOfString:@"\n" withString:@" "]];
		}
	}
	[self finish:self.run state:s];
}

- (void)authorizationController:(ASAuthorizationController *)controller didCompleteWithError:(NSError *)error {
	if (controller != self.apple) {
		return;
	}
	self.apple = nil;
	[self finish:self.run state:error.code == ASAuthorizationErrorCanceled ? @"cancel" : [NSString stringWithFormat:@"error:%ld %@", (long)error.code, error.localizedDescription]];
}

- (BOOL)openTab:(NSString *)url {
	NSURL *u = url ? [NSURL URLWithString:url] : nil;
	if (!u) {
		return NO;
	}
	NSInteger mine = ++self.run;
	self.state = @"tab";
	dispatch_async(dispatch_get_main_queue(), ^{
		if (mine != self.run) {
			return;
		}
		__weak EARSignIn *weak = self;
		ASWebAuthenticationSession *w = [[ASWebAuthenticationSession alloc] initWithURL:u callbackURLScheme:@"emeraldbreak"
				completionHandler:^(NSURL *callback, NSError *error) {
					EARSignIn *me = weak;
					if (!me || mine != me.run) {
						return;
					}
					me.web = nil;
					if (callback) {
						NSString *r = @"";
						for (NSURLQueryItem *q in [NSURLComponents componentsWithURL:callback resolvingAgainstBaseURL:NO].queryItems) {
							if ([q.name isEqualToString:@"r"]) {
								r = q.value ?: @"";
							}
						}
						[me finish:mine state:[@"tab_done:" stringByAppendingString:r]];
					} else if (error.code == ASWebAuthenticationSessionErrorCodeCanceledLogin) {
						[me finish:mine state:@"tab_closed"];
					} else {
						[me finish:mine state:[NSString stringWithFormat:@"error:%ld %@", (long)error.code, error.localizedDescription]];
					}
				}];
		w.presentationContextProvider = self;
		self.web = w;
		if (![w start]) {
			self.web = nil;
			[self finish:mine state:@"error:the sign-in sheet did not open"];
		}
	});
	return YES;
}

- (void)cancel {
	self.run = self.run + 1;
	self.state = @"";
	dispatch_async(dispatch_get_main_queue(), ^{
		if (self.web) {
			[self.web cancel];
			self.web = nil;
		}
		if (self.apple) {
			if (@available(iOS 16.0, *)) {
				[self.apple cancel];
			}
			self.apple = nil;
		}
	});
}

@end

static EARSignIn *ear_sign_in() {
	static EARSignIn *s = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		s = [EARSignIn new];
	});
	return s;
}

// ------------------------------------------------------------------ Game Center sign-in (26 Nov 2026)
// Randy: "I kind of like among us's sign in which auto logs in the player with their apple or google play account".
// The player's Game Center account signs them in by itself: iOS shows its "Welcome back" banner, or its own Game Center
// sign-in sheet when the phone isn't signed in (only when the game asks with interactive = true). Apple then signs
// (teamPlayerID + bundle id + timestamp + salt); the game's server checks that signature with Apple's certificate.
// platformState(): "" idle, "busy", "gc:{json}", "none" (no Game Center player), "cancel", "error:...".
@interface EARGameCenter : NSObject
@property(atomic, copy) NSString *state;
@property(atomic) NSInteger run;
@property(atomic) BOOL handlerSet;
@property(atomic) BOOL interactive;
@property(nonatomic, strong) UIViewController *pending;
@end

@implementation EARGameCenter

- (instancetype)init {
	if ((self = [super init])) {
		_state = @"";
	}
	return self;
}

- (void)finish:(NSInteger)mine state:(NSString *)s {
	if (mine == self.run) {
		self.state = s;
		NSLog(@"[EmeraldAR] game center: %@", [s hasPrefix:@"gc:"] ? @"signed in" : s);
	}
}

- (void)present:(UIViewController *)vc {
	UIViewController *top = ear_key_window().rootViewController;
	while (top.presentedViewController) {
		top = top.presentedViewController;
	}
	if (top) {
		[top presentViewController:vc animated:YES completion:nil];
	}
}

- (BOOL)start:(BOOL)interactive {
	NSInteger mine = ++self.run;
	self.state = @"busy";
	self.interactive = interactive;
	dispatch_async(dispatch_get_main_queue(), ^{
		if (mine != self.run) {
			return;
		}
		GKLocalPlayer *lp = GKLocalPlayer.localPlayer;
		if (lp.isAuthenticated) {
			[self verify:mine];
			return;
		}
		if (self.handlerSet) {
			// (iOS calls the handler once per launch and again when the player signs in; a sheet it handed us earlier
			// can still be shown)
			if (self.pending && interactive) {
				UIViewController *vc = self.pending;
				self.pending = nil;
				[self present:vc];
			} else {
				[self finish:mine state:@"none"];
			}
			return;
		}
		self.handlerSet = YES;
		__weak EARGameCenter *weak = self;
		lp.authenticateHandler = ^(UIViewController *vc, NSError *error) {
			EARGameCenter *me = weak;
			if (!me) {
				return;
			}
			if (vc) {
				if (me.interactive) {
					[me present:vc];
				} else {
					me.pending = vc;
					[me finish:me.run state:@"none"];
				}
				return;
			}
			if (GKLocalPlayer.localPlayer.isAuthenticated) {
				[me verify:me.run];
			} else if (error.code == GKErrorCancelled) {
				[me finish:me.run state:@"cancel"];
			} else if (error) {
				[me finish:me.run state:[NSString stringWithFormat:@"error:%ld %@", (long)error.code, error.localizedDescription]];
			} else {
				[me finish:me.run state:@"none"];
			}
		};
	});
	return YES;
}

- (void)verify:(NSInteger)mine {
	GKLocalPlayer *lp = GKLocalPlayer.localPlayer;
	[lp fetchItemsForIdentityVerificationSignature:^(NSURL *url, NSData *sig, NSData *salt, uint64_t ts, NSError *error) {
		if (error || !url || !sig || !salt) {
			[self finish:mine state:[NSString stringWithFormat:@"error:%ld %@", (long)error.code, error.localizedDescription ?: @"no signature"]];
			return;
		}
		NSDictionary *d = @{
			@"url" : url.absoluteString ?: @"",
			@"sig" : [sig base64EncodedStringWithOptions:0],
			@"salt" : [salt base64EncodedStringWithOptions:0],
			@"ts" : [NSString stringWithFormat:@"%llu", ts],
			@"team_id" : lp.teamPlayerID ?: @"",
			@"bundle" : NSBundle.mainBundle.bundleIdentifier ?: @"",
			@"alias" : lp.alias ?: @"",
		};
		NSData *j = [NSJSONSerialization dataWithJSONObject:d options:0 error:nil];
		NSString *js = j ? [[NSString alloc] initWithData:j encoding:NSUTF8StringEncoding] : nil;
		[self finish:mine state:js ? [@"gc:" stringByAppendingString:js] : @"error:json"];
	}];
}

- (void)cancel {
	self.run = self.run + 1;
	self.state = @"";
}

@end

static EARGameCenter *ear_game_center() {
	static EARGameCenter *g = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		g = [EARGameCenter new];
	});
	return g;
}

#define EAR_HOST ((__bridge EARHost *)host)

namespace godot {

EmeraldAR::EmeraldAR() {
	host = (__bridge_retained void *)[EARHost new];
}

EmeraldAR::~EmeraldAR() {
	if (host) {
		EARHost *h = (__bridge_transfer EARHost *)host;
		[h stop];
		host = nullptr;
	}
}

String EmeraldAR::availability() {
	return ear_str([EAR_HOST availability]);
}

bool EmeraldAR::requestInstall() {
	return false; // ARKit is part of iOS: nothing to install
}

bool EmeraldAR::openAppSettings() {
	return [EAR_HOST openAppSettings];
}

// v1.1.15: the iPhone's share sheet with a short text and the game's link (nothing is tracked).
bool EmeraldAR::share(const String &p_text, const String &p_title) {
	NSString *text = [NSString stringWithUTF8String:p_text.utf8().get_data()];
	(void)p_title;
	dispatch_async(dispatch_get_main_queue(), ^{
		UIViewController *top = nil;
		for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
			if ([scene isKindOfClass:[UIWindowScene class]]) {
				for (UIWindow *w in ((UIWindowScene *)scene).windows) {
					if (w.isKeyWindow) {
						top = w.rootViewController;
					}
				}
			}
		}
		while (top && top.presentedViewController) {
			top = top.presentedViewController;
		}
		if (!top || !text) {
			return;
		}
		UIActivityViewController *sheet = [[UIActivityViewController alloc] initWithActivityItems:@[ text ] applicationActivities:nil];
		// iPad: the sheet is a popover and needs a place to point at
		if (sheet.popoverPresentationController) {
			sheet.popoverPresentationController.sourceView = top.view;
			CGRect b = top.view.bounds;
			sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(b), CGRectGetMidY(b), 1, 1);
			sheet.popoverPresentationController.permittedArrowDirections = 0;
		}
		[top presentViewController:sheet animated:YES completion:nil];
	});
	return text != nil;
}

// 24 Nov 2026: sign in with Apple (Apple's own sheet) / Google, Facebook (the iPhone's sign-in sheet). See EARSignIn.
bool EmeraldAR::appleSignIn(const String &p_nonce) {
	return [ear_sign_in() appleWithNonce:[NSString stringWithUTF8String:p_nonce.utf8().get_data()]];
}

bool EmeraldAR::openAuthTab(const String &p_url, const String &p_status_url, const String &p_k) {
	(void)p_status_url;   // (the sheet sees the end of the sign-in itself: the server ends it on emeraldbreak://auth)
	(void)p_k;
	return [ear_sign_in() openTab:[NSString stringWithUTF8String:p_url.utf8().get_data()]];
}

String EmeraldAR::signInState() {
	return ear_str(ear_sign_in().state);
}

void EmeraldAR::signInCancel() {
	[ear_sign_in() cancel];
}

// 26 Nov 2026: the automatic sign-in with the phone's game account (Game Center here). See EARGameCenter.
bool EmeraldAR::platformSignIn(const String &p_server_client_id, bool p_interactive) {
	(void)p_server_client_id;   // (Android's Play Games needs it; Game Center doesn't)
	return [ear_game_center() start:p_interactive];
}

String EmeraldAR::platformState() {
	return ear_str(ear_game_center().state);
}

void EmeraldAR::platformCancel() {
	[ear_game_center() cancel];
}

// ---- 27 Nov 2026: Firebase Analytics + Crashlytics, for the game's Analytics autoload. The Firebase SDK is linked into
// the app by ios_plugin/ci.sh (CocoaPods) with GoogleService-Info.plist; this library only finds it by name at run time
// (NSClassFromString), so it builds without Firebase's headers and an app without Firebase just says "not available".
// Collection starts OFF (Info.plist keys from make_preset.py); analyticsSetEnabled follows the player's choice. Consent:
// analytics storage as chosen, advertising storage / user data / personalisation always denied. No IDFA, no tracking.
static id ear_fb_analytics() { return NSClassFromString(@"FIRAnalytics"); }

static bool ear_fb_ready() {
	Class app = NSClassFromString(@"FIRApp");
	if (app == nil || ear_fb_analytics() == nil) {
		return false;
	}
	if ([NSBundle.mainBundle pathForResource:@"GoogleService-Info" ofType:@"plist"] == nil) {
		return false;
	}
	if ([app performSelector:@selector(defaultApp)] == nil) {
		@try {
			[app performSelector:@selector(configure)];
		} @catch (NSException *e) {
			NSLog(@"[EmeraldAR] Firebase configure failed: %@", e);
			return false;
		}
	}
	return true;
}

static id ear_fb_crashlytics() {
	Class c = NSClassFromString(@"FIRCrashlytics");
	return c ? [c performSelector:@selector(crashlytics)] : nil;
}

bool EmeraldAR::analyticsAvailable() {
	return ear_fb_ready();
}

void EmeraldAR::analyticsSetEnabled(bool p_on) {
	if (!ear_fb_ready()) {
		return;
	}
	id fa = ear_fb_analytics();
	NSDictionary *consent = @{@"analytics_storage": p_on ? @"granted" : @"denied", @"ad_storage": @"denied",
		@"ad_user_data": @"denied", @"ad_personalization": @"denied"};
	if ([fa respondsToSelector:@selector(setConsent:)]) {
		[fa performSelector:@selector(setConsent:) withObject:consent];
	}
	((void (*)(id, SEL, BOOL))objc_msgSend)(fa, @selector(setAnalyticsCollectionEnabled:), p_on ? YES : NO);
	id cr = ear_fb_crashlytics();
	if (cr && [cr respondsToSelector:@selector(setCrashlyticsCollectionEnabled:)]) {
		((void (*)(id, SEL, BOOL))objc_msgSend)(cr, @selector(setCrashlyticsCollectionEnabled:), p_on ? YES : NO);
	}
	NSLog(@"[EmeraldAR] Firebase collection %@", p_on ? @"on" : @"off");
}

void EmeraldAR::analyticsLog(const String &p_name, const String &p_json) {
	if (!ear_fb_ready()) {
		return;
	}
	NSString *name = [NSString stringWithUTF8String:p_name.utf8().get_data()];
	NSData *data = [NSData dataWithBytes:p_json.utf8().get_data() length:p_json.utf8().length()];
	NSDictionary *params = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
	if (![params isKindOfClass:[NSDictionary class]]) {
		params = @{};
	}
	[ear_fb_analytics() performSelector:@selector(logEventWithName:parameters:) withObject:name withObject:params];
}

void EmeraldAR::crashlyticsLog(const String &p_text) {
	id cr = ear_fb_crashlytics();
	if (cr && [cr respondsToSelector:@selector(log:)]) {
		[cr performSelector:@selector(log:) withObject:[NSString stringWithUTF8String:p_text.utf8().get_data()]];
	}
}

String EmeraldAR::getLastError() {
	return ear_str([EAR_HOST lastError]);
}

String EmeraldAR::getInfo() {
	return ear_str([EAR_HOST info]);
}

bool EmeraldAR::start(int p_w, int p_h) {
	return [EAR_HOST startWidth:p_w height:p_h];
}

void EmeraldAR::stop() {
	[EAR_HOST stop];
}

void EmeraldAR::setViewSize(int p_w, int p_h) {
	[EAR_HOST setViewWidth:p_w height:p_h];
}

PackedFloat32Array EmeraldAR::getState() {
	PackedFloat32Array a;
	a.resize(EAR_STATE_LEN);
	[EAR_HOST fillState:a.ptrw()];
	return a;
}

PackedByteArray EmeraldAR::getImageY() {
	return [EAR_HOST imageY];
}

PackedByteArray EmeraldAR::getImageUV() {
	return [EAR_HOST imageUV];
}

bool EmeraldAR::placeAnchor(const PackedFloat32Array &p_pose) {
	if (p_pose.size() < 7) {
		return false;
	}
	return [EAR_HOST placeAnchor:p_pose.ptr()];
}

void EmeraldAR::clearAnchor() {
	[EAR_HOST clearAnchor];
}

void EmeraldAR::_bind_methods() {
	ClassDB::bind_method(D_METHOD("availability"), &EmeraldAR::availability);
	ClassDB::bind_method(D_METHOD("requestInstall"), &EmeraldAR::requestInstall);
	ClassDB::bind_method(D_METHOD("openAppSettings"), &EmeraldAR::openAppSettings);
	ClassDB::bind_method(D_METHOD("share", "text", "title"), &EmeraldAR::share);
	ClassDB::bind_method(D_METHOD("appleSignIn", "nonce"), &EmeraldAR::appleSignIn);
	ClassDB::bind_method(D_METHOD("openAuthTab", "url", "status_url", "k"), &EmeraldAR::openAuthTab);
	ClassDB::bind_method(D_METHOD("signInState"), &EmeraldAR::signInState);
	ClassDB::bind_method(D_METHOD("signInCancel"), &EmeraldAR::signInCancel);
	ClassDB::bind_method(D_METHOD("platformSignIn", "server_client_id", "interactive"), &EmeraldAR::platformSignIn);
	ClassDB::bind_method(D_METHOD("platformState"), &EmeraldAR::platformState);
	ClassDB::bind_method(D_METHOD("platformCancel"), &EmeraldAR::platformCancel);
	ClassDB::bind_method(D_METHOD("analyticsAvailable"), &EmeraldAR::analyticsAvailable);
	ClassDB::bind_method(D_METHOD("analyticsSetEnabled", "on"), &EmeraldAR::analyticsSetEnabled);
	ClassDB::bind_method(D_METHOD("analyticsLog", "name", "json"), &EmeraldAR::analyticsLog);
	ClassDB::bind_method(D_METHOD("crashlyticsLog", "text"), &EmeraldAR::crashlyticsLog);
	ClassDB::bind_method(D_METHOD("getLastError"), &EmeraldAR::getLastError);
	ClassDB::bind_method(D_METHOD("getInfo"), &EmeraldAR::getInfo);
	ClassDB::bind_method(D_METHOD("start", "w", "h"), &EmeraldAR::start);
	ClassDB::bind_method(D_METHOD("stop"), &EmeraldAR::stop);
	ClassDB::bind_method(D_METHOD("setViewSize", "w", "h"), &EmeraldAR::setViewSize);
	ClassDB::bind_method(D_METHOD("getState"), &EmeraldAR::getState);
	ClassDB::bind_method(D_METHOD("getImageY"), &EmeraldAR::getImageY);
	ClassDB::bind_method(D_METHOD("getImageUV"), &EmeraldAR::getImageUV);
	ClassDB::bind_method(D_METHOD("placeAnchor", "pose"), &EmeraldAR::placeAnchor);
	ClassDB::bind_method(D_METHOD("clearAnchor"), &EmeraldAR::clearAnchor);
}

} // namespace godot

// ------------------------------------------------------------------------------------------ registration
static godot::EmeraldAR *ear_singleton = nullptr;

static void ear_initialize(godot::ModuleInitializationLevel p_level) {
	if (p_level != godot::MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(godot::EmeraldAR);
	ear_singleton = memnew(godot::EmeraldAR);
	godot::Engine::get_singleton()->register_singleton("EmeraldAR", ear_singleton);
}

static void ear_terminate(godot::ModuleInitializationLevel p_level) {
	if (p_level != godot::MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	if (ear_singleton) {
		godot::Engine::get_singleton()->unregister_singleton("EmeraldAR");
		memdelete(ear_singleton);
		ear_singleton = nullptr;
	}
}

extern "C" {
GDExtensionBool GDE_EXPORT emeraldar_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(ear_initialize);
	init_obj.register_terminator(ear_terminate);
	init_obj.set_minimum_library_initialization_level(godot::MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
