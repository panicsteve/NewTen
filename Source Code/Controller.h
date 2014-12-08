@class NewtonConnection;

@interface Controller : NSObject
{
    IBOutlet NSPopUpButton* driverButton;
    IBOutlet NSButton* installPackageButton;
	IBOutlet NSWindow* mainWindow;
	IBOutlet NSProgressIndicator* progress;
	IBOutlet NSTextField* status;
	IBOutlet NSPanel* sheet;
	
	NewtonConnection* connection;
	volatile BOOL giveUp;
//	NSString* driver;
//	NSString* package;
}

- (IBAction)installPackage:(id)sender;
- (IBAction)scanForSerialDrivers:(id)sender;
- (IBAction)selectDriver:(id)sender;
- (IBAction)selectPackage:(id)sender;

@end
