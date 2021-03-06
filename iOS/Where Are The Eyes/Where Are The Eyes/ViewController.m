//
//  ViewController.m
//  Where Are The Eyes
//
//  Created by Milo Trujillo on 3/23/16.
//  Copyright © 2016 Daylighting Society. All rights reserved.
//

#import "ViewController.h"
#import "Constants.h"
#import "MarkPin.h"
#import "Score.h"
@import Mapbox;

@interface ViewController () <MGLMapViewDelegate>
	@property (strong) IBOutlet MGLMapView* map;
	@property (weak, nonatomic) IBOutlet UIView* scorebar;
	@property (strong) IBOutlet UILabel* usernameLabel;
	@property (strong) IBOutlet UILabel* camerasMarkedLabel;
	@property (strong) IBOutlet UILabel* verificationsLabel;
@end

@implementation ViewController

// Initial setup code goes here
- (void)viewDidLoad {
    [super viewDidLoad];

	//
	// First we initialize the map
	//
	
	//NSURL* styleURL = [MGLStyle satelliteStyleURL];
	[self.map setCenterCoordinate:CLLocationCoordinate2DMake(59.31, 18.06)
						zoomLevel:9
						 animated:NO];
	[self.map setDelegate:self];
	//[self.map setStyleURL:styleURL];
	gps = [[GPS alloc] init:self.map];
	scores = [[Score alloc] init];
	
	
	//
	// Then we validate our current configuration
	//
	[self sanitizeUsername];
	
	//
	// Finally we register a few event handlers
	//
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(displayInvalidUserAlert:)
												 name:@"InvalidLogin"
											   object:nil];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(displayCameraOutOfRangeAlert:)
												 name:@"CameraOutOfRange"
											   object:nil];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(displayMarkingErrorAlert:)
												 name:@"ErrorMarkingCamera"
											   object:nil];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(updateScore:)
												 name:@"UpdateScore"
											   object:nil];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(settingsChanged:)
												 name:NSUserDefaultsDidChangeNotification
											   object:nil];

	if( [scores scoresEnabled] )
		[scores updateScores:self.getUsername];

}

- (void)viewDidAppear:(BOOL)animated
{
	[super viewDidAppear:animated];
	UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
	[self redrawScores:orientation];
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
	[self redrawScores:toInterfaceOrientation];
}

- (void)redrawScores:(UIInterfaceOrientation)orientation
{
	// And now, right before the UI is actually drawn, lets make some corrections
	[self.view sendSubviewToBack:self.map];
	[box removeFromSuperview];
	if( [scores scoresEnabled] )
	{
		CGRect windowSize = self.view.window.frame;
		// If we're in portrait mode we need to make room for the status bar at the top
		if( orientation == UIInterfaceOrientationPortrait )
			box = [[UIView alloc] initWithFrame:CGRectMake(0, 20, windowSize.size.width, 20)];
		else
			box = [[UIView alloc] initWithFrame:CGRectMake(0, 0, windowSize.size.height, 20)];
		box.backgroundColor = [UIColor whiteColor];

		// Add a line on the bottom before the map starts
		// NOTE: Coordinates are relative to 'box', so a Y of '20' is always correct.
		CALayer* boxBorder = [CALayer layer];
		boxBorder.backgroundColor = [[UIColor lightGrayColor] CGColor];
		boxBorder.frame = CGRectMake(0, 20, box.frame.size.width, 1);
		[box.layer addSublayer:boxBorder];

		[self.view addSubview:box];
		[self.view bringSubviewToFront:self.scorebar];
		[self.scorebar setHidden:false];
		[self.usernameLabel setText:[self getUsername]];
		NSLog(@"Scores are enabled!");
	} else {
		[box setHidden:true];
		[self.scorebar setHidden:true];
		NSLog(@"Scores are disabled.");
	}
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

// This is part of being a MapView delegate, and would return a custom image
// for pins if we wanted.
- (MGLAnnotationImage*)mapView:(MGLMapView*)mapView imageForAnnotation:(id<MGLAnnotation>)annotation {
	MGLAnnotationImage* pinImage = [mapView dequeueReusableAnnotationImageWithIdentifier:@"map_pin"];
	if( !pinImage )
	{
		UIImage* img = [UIImage imageNamed:@"map_pin"];
		
		// Usually images have the lower half transparency, to make sure the pin tip is
		// the center anchor-point of the image. However, we don't want the transparancy to be "clickable"
		// so we make a new image of appropriate size.
		img = [img imageWithAlignmentRectInsets:UIEdgeInsetsMake(0, 0, img.size.height/2, 0)];
		
		// Initialize the pinImage with the image we just loaded
		pinImage = [MGLAnnotationImage annotationImageWithImage:img reuseIdentifier:@"map_pin"];
	}
	return pinImage;
}

// Enable displaying pin annotations when they are tapped on.
- (BOOL)mapView:(MGLMapView*)mapView annotationCanShowCallout:(id<MGLAnnotation>)annotation {
	return YES;
}

// Opens the iOS settings pane for our app
- (IBAction)openSettings:(id)sender
{
	NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
	[[UIApplication sharedApplication] openURL:url];
}

// Returns the current username
- (NSString*)getUsername
{
	NSString* username = [[NSUserDefaults standardUserDefaults] stringForKey:kUsernameString];
	return username;
}

// Modifies the username setting if it contains illegal characters
- (NSString*)sanitizeUsername
{
	NSString* username = [[NSUserDefaults standardUserDefaults] stringForKey:kUsernameString];
	if( username == nil )
	{
		NSLog(@"Tried to read username, but got nil");
		return nil;
	}
	// Alright, so there *is* a username set.
	// We only allow alphanumeric data, so let's strip everything else
	NSString* validCharacters = @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopq‌​rstuvwxyz0123456789_";
	NSCharacterSet *charactersToRemove = [[NSCharacterSet characterSetWithCharactersInString:validCharacters] invertedSet];
	NSString *strippedReplacement = [[username componentsSeparatedByCharactersInSet:charactersToRemove] componentsJoinedByString:@""];
	NSLog(@"Read username: %@", username);
	if( ![username isEqualToString:strippedReplacement] )
	{
		// Update the configured username
		NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
		[defaults setObject:strippedReplacement
					 forKey:kUsernameString];
		
		NSLog(@"Rewrote username as: %@", strippedReplacement);
		
		return strippedReplacement;
	}
	return username;
}

- (IBAction)eyePressed:(id)sender
{
	BOOL confirmation_enabled = [[NSUserDefaults standardUserDefaults] boolForKey:kConfirmMarkingCameras];

	// Always recenter when marking a pin so users aren't misled about where it will go
	[self recenterMap];

	// Present a confirmation if asked for, otherwise just go for it and mark the pin.
	if( confirmation_enabled )
	{
		UIAlertController* confirm = [UIAlertController alertControllerWithTitle:@"Confirm"
																		 message:@"Mark a camera at this location?"
																  preferredStyle:UIAlertControllerStyleAlert];
		
		UIAlertAction* cancel = [UIAlertAction actionWithTitle:@"No"
														 style:UIAlertActionStyleCancel
													   handler:^(UIAlertAction* action) {}];
		
		UIAlertAction* mark = [UIAlertAction actionWithTitle:@"Yes"
																   style:UIAlertActionStyleDefault
																 handler:^(UIAlertAction* action) {
																	 [self markPin];
																 }];
		
		[confirm addAction:cancel];
		[confirm addAction:mark];
		[self presentViewController:confirm animated:YES completion:nil];
		
	} else {
		[self markPin];
	}
}

// When settings change we reset the score system
- (void)settingsChanged:(NSNotification*) notification {
	NSString* username = [self sanitizeUsername];
	UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
	if( ![scores scoresWereEnabled] && [scores scoresEnabled] ) {
		NSLog(@"Scores were just enabled. Updating...");
		[scores updateScores:username];
	}
	if( [scores scoresEnabled] && [scores usernameChanged:username] ) {
		NSLog(@"Scores are enabled and username has changed! Redownloading score...");
		[scores updateScores:username];
	}
	[self redrawScores:orientation];
	[_usernameLabel setText:self.getUsername];
}

// Displays an error if the username was rejected by server when marking a pin
- (void)displayInvalidUserAlert:(NSNotification*) notification {
	UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Marking camera failed"
																   message:@"Your username is not recognized at eyes.daylightingsociety.org. Is it registered on our website?"
															preferredStyle:UIAlertControllerStyleAlert];
	
	UIAlertAction* cancel = [UIAlertAction actionWithTitle:@"Okay"
													 style:UIAlertActionStyleCancel
												   handler:^(UIAlertAction* action) {}];
	
	UIAlertAction* registerUsername = [UIAlertAction actionWithTitle:@"Register"
															   style:UIAlertActionStyleDefault
															 handler:^(UIAlertAction* action) {
																 [[UIApplication sharedApplication] openURL:[NSURL URLWithString: kRegisterURL]];
															 }];
	
	
	[alert addAction:cancel];
	[alert addAction:registerUsername];
	[self presentViewController:alert animated:YES completion:nil];
}

// Displays an error when the user marks a camera far from their physical location
// It probably means they're using a proxy, but could also mean they're spoofing their
// location with dev tools.
- (void)displayCameraOutOfRangeAlert:(NSNotification*) notification {
	UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Marking camera failed"
																   message:@"Your IP address and physical location do not match. To protect the integrity of the map we cannot allow you to mark pins with a proxy."
															preferredStyle:UIAlertControllerStyleAlert];

	UIAlertAction* cancel = [UIAlertAction actionWithTitle:@"Okay"
													 style:UIAlertActionStyleCancel
												   handler:^(UIAlertAction* action) {}];


	[alert addAction:cancel];
	[self presentViewController:alert animated:YES completion:nil];
}

// Displays any generic error received when marking pins. Mostly exists as a future-proof for undefined errors.
- (void)displayMarkingErrorAlert:(NSNotification*) notification {
	UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Marking camera failed"
																   message:@"Unknown error, or server unreachable."
															preferredStyle:UIAlertControllerStyleAlert];
	
	UIAlertAction* cancel = [UIAlertAction actionWithTitle:@"Okay"
													 style:UIAlertActionStyleCancel
												   handler:^(UIAlertAction* action) {}];
	
	
	[alert addAction:cancel];
	[self presentViewController:alert animated:YES completion:nil];
}

// Updates the score on the main thread
- (void)updateScore:(NSNotification*) notification {
	NSString* cameras_marked = [[NSString alloc] initWithFormat:@"%d",[scores getCameras]];
	NSString* verifications = [[NSString alloc] initWithFormat:@"%d",[scores getVerifications]];
	dispatch_block_t update = ^{
		[self.camerasMarkedLabel setText:cameras_marked];
		[self.verificationsLabel setText:verifications];
	};
	if( [NSThread isMainThread] )
		update();
	else
		dispatch_sync(dispatch_get_main_queue(), update);
}

- (void)displayNoUsernameAlert
{
	UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"No username set"
																   message:@"Please register a username online and set it in Settings"
															preferredStyle:UIAlertControllerStyleAlert];
	
	UIAlertAction* cancel = [UIAlertAction actionWithTitle:@"Dismiss"
													 style:UIAlertActionStyleCancel
												   handler:^(UIAlertAction* action) {}];
	
	UIAlertAction* registerUsername = [UIAlertAction actionWithTitle:@"Register"
															   style:UIAlertActionStyleDefault
															 handler:^(UIAlertAction* action) {
																 [[UIApplication sharedApplication] openURL:[NSURL URLWithString: kRegisterURL]];
															 }];
	
	[alert addAction:cancel];
	[alert addAction:registerUsername];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)markPin
{
	NSString* username = [self getUsername];
	if( username == nil )
	{
		[self displayNoUsernameAlert];
		return;
	}
	CLLocationCoordinate2D coord = [gps lastCoord];
	Coord* c = [[Coord alloc] initLatitude:coord.latitude longitude:coord.longitude confirmations:0];
	
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		[MarkPin markPinAt:c withUsername:username];
		[NSThread sleepForTimeInterval:kTimeoutAfterPosting];
		[gps forcePinUpdate];
		if( [scores scoresEnabled] )
			[scores updateScores:self.getUsername];
	});	
}

- (void)recenterMap
{
	[self.map setCenterCoordinate:[gps lastCoord]];
}

@end
