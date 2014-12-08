#import "Controller.h"
#import "NewtonConnection.h"

//
// Based on UnixNPI by
// Richard C.I. Li, Chayim I. Kirshen, Victor Rehorst
// Objective-C adaptation by Steven Frank <stevenf@panic.com>
//

static unsigned char lrFrame[] = 
{
	'\x17', // Length of header 
	'\x01', // Type indication LR frame 
	'\x02', // Constant parameter 1 
	'\x01', '\x06', '\x01', '\x00', '\x00', '\x00', '\x00', '\xff', // Constant parameter 2 
	'\x02', '\x01', '\x02', // Octet-oriented framing mode 
	'\x03', '\x01', '\x01', // k = 1 
	'\x04', '\x02', '\x40', '\x00', // N401 = 64 
	'\x08', '\x01', '\x03' // N401 = 256 & fixed LT, LA frames 
};


@interface Controller (Private)

- (BOOL)installPackagesThread:(NSDictionary*)args;
- (void)updateStatus:(NSString*)statusText;
- (void)updateProgress:(NSNumber*)current;
- (void)updateProgressMax:(NSNumber*)maximum;

@end


@implementation Controller


- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
//
// Quit if window closed
//
{
	return YES;
}


- (void)awakeFromNib
//
// Things to do on launch
//
{
	[self scanForSerialDrivers:self];

	NSString* preferredPort = [[NSUserDefaults standardUserDefaults] objectForKey:@"PreferredPort"];

	if ( preferredPort )
	{
		if ( preferredPort != nil )
		{
			int index = [driverButton indexOfItemWithRepresentedObject:preferredPort];
			
			if ( index == - 1 )
				index = 0;
				
			[driverButton selectItemAtIndex:index];
		}
	}
	
	[self selectDriver:self];
	[mainWindow setFrameAutosaveName:@"MainWindow"];
	
	[mainWindow registerForDraggedTypes:[NSArray arrayWithObject:NSFilenamesPboardType]];
}


- (IBAction)cancelInstall:(id)sender
{	
	[connection cancel];
	giveUp = YES;
}


- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
//
// We accept all file drags
//
{
	return NSDragOperationCopy;
}


- (void)hideInstallSheet
{
	[NSApp endSheet:sheet];
	[sheet orderOut:self];
}


- (IBAction)installPackage:(id)sender
//
// Called when "Install Package" clicked
//
{
	[NSApp beginSheet:sheet modalForWindow:mainWindow modalDelegate:nil didEndSelector:nil contextInfo:nil];
}


- (BOOL)installPackagesThread:(NSDictionary*)args
//
// Install the given packages
//
{
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

	FILE* inFile;
	long inFileLen;
	long tmpFileLen;
	unsigned char sendBuf[MAX_HEAD_LEN + MAX_INFO_LEN];
	unsigned char recvBuf[MAX_HEAD_LEN + MAX_INFO_LEN];
	unsigned char ltSeqNo = 0;
	int i, j;
	int speed = 38400;
	BOOL success = NO;
	NSArray* packages = [args objectForKey:@"Packages"];
	NSString* devicePath = [args objectForKey:@"DevicePath"];
	
	giveUp = NO;

	[self performSelectorOnMainThread:@selector(showInstallSheet) withObject:nil waitUntilDone:YES];
	
	[self performSelectorOnMainThread:@selector(updateProgress:) withObject:[NSNumber numberWithInt:0] 
				waitUntilDone:YES];

	[self performSelectorOnMainThread:@selector(updateProgressMax:) withObject:[NSNumber numberWithInt:100] 
				waitUntilDone:YES];

	[self performSelectorOnMainThread:@selector(updateStatus:) 
				withObject:@"Setting up serial port..."
				waitUntilDone:YES];

	connection = [NewtonConnection connectionWithDevicePath:devicePath speed:speed];

	// Wait for Newton to connect
	
	[self performSelectorOnMainThread:@selector(updateStatus:) 
				withObject:@"Waiting for Newton Dock connection..." 
				waitUntilDone:YES];
	
	do 
	{
		while ( [connection receiveFrame:recvBuf] < 0 )
		{
			if ( giveUp )
				break;
		}

		if ( giveUp )
			break;
	} 
	while ( recvBuf[1] != '\x01' );

	if ( giveUp )
		goto bail;

	[self performSelectorOnMainThread:@selector(updateStatus:) 
				withObject:@"Handshaking..." 
				waitUntilDone:YES];
	
	// Send LR frame 

	//	alarm(TimeOut);
	do 
	{
		[connection sendFrame:NULL header:lrFrame length:0];
	} 
	while ( [connection waitForLAFrame:ltSeqNo] < 0 && !giveUp );
		
	if ( giveUp )	
		goto bail;
		
	++ltSeqNo;
	
	// Wait LT frame newtdockrtdk 
	
	while ( [connection receiveFrame:recvBuf] < 0 || recvBuf[1] != '\x04' )
	{
	}
	
	[connection sendLAFrame:recvBuf[2]];

	// Send LT frame newtdockdock 

	//	alarm(TimeOut);
	do 
	{
		[connection sendLTFrame:(unsigned char*)"newtdockdock\0\0\0\4\0\0\0\4" length:20 seqNo:ltSeqNo];
	} 
	while ( [connection waitForLAFrame:ltSeqNo] < 0 );

	++ltSeqNo;
	
	// Wait LT frame newtdockname 

	//	alarm(TimeOut);
	while ( (([connection receiveFrame:recvBuf] < 0) || (recvBuf[1] != '\x04')) && !giveUp )
	{
	}
	
	if ( giveUp )	
		goto bail;
		
	[connection sendLAFrame:recvBuf[2]];
	
	// Get owner name 

	i = recvBuf[19] * 256 * 256 * 256 + recvBuf[20] * 256 * 256 + recvBuf[21] *
		256 + recvBuf[22];

	i += 24;
	j = 0;

	while ( recvBuf[i] != '\0' ) 
	{
		sendBuf[j] = recvBuf[i];
		j++;
		i += 2;
	}
	sendBuf[j] = '\0';

	//NSLog([NSString stringWithCString:(char*)sendBuf]);

	// Send LT frame newtdockstim 

	//	alarm(TimeOut);
	do 
	{
		[connection sendLTFrame:(unsigned char*)"newtdockstim\0\0\0\4\0\0\0\x1e" length:20 seqNo:ltSeqNo];
	} 
	while ( [connection waitForLAFrame:ltSeqNo] < 0 && !giveUp );

	if ( giveUp )	
		goto bail;
		
	++ltSeqNo;

	// Wait LT frame newtdockdres 
	//	alarm(TimeOut);
	while( (([connection receiveFrame:recvBuf] < 0) || (recvBuf[1] != '\x04')) && !giveUp )
	{
	}
	
	if ( giveUp )	
		goto bail;
		
	[connection sendLAFrame:recvBuf[2]];

	// batch install all of the files 
	
	NSEnumerator* enumerator = [packages objectEnumerator];
	NSString* package;
	
	while ( (package = [enumerator nextObject]) )
	{
		if ( (inFile = fopen([package fileSystemRepresentation], "rb")) == NULL )
		{
			//ErrHandler("Error in opening package file!!");
			goto bail;
		}
		
		fseek(inFile, 0, SEEK_END);
		inFileLen = ftell(inFile);
		rewind(inFile);

		//printf("File is '%s'\n", argv[k]);

		// Send LT frame newtdocklpkg 
		//		alarm(TimeOut);
		
		strcpy((char*)sendBuf, "newtdocklpkg");
		tmpFileLen = inFileLen;
		for ( i = 15; i >= 12; i-- ) 
		{
			sendBuf[i] = tmpFileLen % 256;
			tmpFileLen /= 256;
		}
		
		do 
		{
			[connection sendLTFrame:sendBuf length:16 seqNo:ltSeqNo];
		} 
		while ( [connection waitForLAFrame:ltSeqNo] < 0 && !giveUp );
		
		if ( giveUp )	
			goto bail;
			
		++ltSeqNo;

		[self performSelectorOnMainThread:@selector(updateStatus:) 
					withObject:@"Installing package..." 
					waitUntilDone:YES];

		[self performSelectorOnMainThread:@selector(updateProgressMax:) withObject:[NSNumber numberWithInt:inFileLen] 
				waitUntilDone:YES];
	
		// Send package data 
		
		while ( !feof(inFile) ) 
		{
//			alarm(TimeOut);

			i = fread(sendBuf, sizeof(unsigned char), MAX_INFO_LEN, inFile);

			while ( i % 4 != 0 )
				sendBuf[i++] = '\0';
				
			do 
			{
				[connection sendLTFrame:sendBuf length:i seqNo:ltSeqNo];
			} 
			while ( [connection waitForLAFrame:ltSeqNo] < 0 && !giveUp );
			
			if ( giveUp )	
				goto bail;
				
			++ltSeqNo;
			
			if ( ltSeqNo % 4 == 0 ) 
			{
				[self performSelectorOnMainThread:@selector(updateProgress:) withObject:[NSNumber numberWithInt:ftell(inFile)] 
						waitUntilDone:YES];
			}
		}

		[self performSelectorOnMainThread:@selector(updateProgress:) withObject:[NSNumber numberWithInt:inFileLen] 
						waitUntilDone:YES];

		// Wait LT frame newtdockdres 
		//		alarm(TimeOut);
		
		while ( (([connection receiveFrame:recvBuf] < 0) || (recvBuf[1] != '\x04')) && !giveUp )
		{
		}
		
		if ( giveUp )	
			goto bail;
			
		[connection sendLAFrame:recvBuf[2]];

		fclose(inFile);
	} 
	
	// Send LT frame newtdockdisc 
	//	alarm(TimeOut);
	do 
	{
		[connection sendLTFrame:(unsigned char*)"newtdockdisc\0\0\0\0" length:16 seqNo:ltSeqNo];
	} 
	while ( [connection waitForLAFrame:ltSeqNo] < 0 && !giveUp );
	
	if ( giveUp )	
		goto bail;
		
	// Wait disconnect 
	//	alarm(0);
	[connection waitForLDFrame];

	[self performSelectorOnMainThread:@selector(updateStatus:) 
				withObject:@"Finished" 
				waitUntilDone:YES];

	success = YES;
	
bail:

	if ( giveUp )
		[connection disconnect];

	[self performSelectorOnMainThread:@selector(hideInstallSheet) withObject:nil waitUntilDone:YES];

	[pool release];
	return success;
}


- (void)packagePanelDidEnd:(NSOpenPanel*)inSheet 
			returnCode:(int)returnCode 
			contextInfo:(void*)contextInfo
//
// Called when open panel closes
//
{
	if ( returnCode == NSOKButton )
	{
		// Get selected files
		
		NSArray* packages = [inSheet filenames];

		// Close sheet
		
		[inSheet orderOut:self];
		
		// Install selected packages
		
		NSMenuItem* item = [driverButton itemAtIndex:[driverButton indexOfSelectedItem]];
		NSString* devicePath = [NSString stringWithFormat:@"/dev/%s", 
									[[item representedObject] fileSystemRepresentation]];

		NSDictionary* args = [NSDictionary dictionaryWithObjectsAndKeys:packages, @"Packages", devicePath, @"DevicePath", nil];
		[NSThread detachNewThreadSelector:@selector(installPackagesThread:) toTarget:self withObject:args];
	}
}


- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender
//
// Called upon file drop
//
{
	NSPasteboard* pb = [sender draggingPasteboard];
	
	// Make sure pasteboard has filenames on it, otherwise bail
	
	if ( ![[pb types] containsObject:NSFilenamesPboardType] )
		return NO;
		
	// Get filename array, and start installing

	NSArray* packages = [pb propertyListForType:NSFilenamesPboardType];

	NSMenuItem* item = [driverButton itemAtIndex:[driverButton indexOfSelectedItem]];
	NSString* devicePath = [NSString stringWithFormat:@"/dev/%s", 
								[[item representedObject] fileSystemRepresentation]];
	
	NSDictionary* args = [NSDictionary dictionaryWithObjectsAndKeys:packages, @"Packages", devicePath, @"DevicePath", nil];
	[NSThread detachNewThreadSelector:@selector(installPackagesThread:) toTarget:self withObject:args];
		
	return YES;
}


- (void)scanForSerialDrivers:(id)sender
//
// Add any item matching cu.* or tty.* from /dev to the 
// serial driver popup menu
//
{
	DIR* dir;
	struct dirent* ent;
	
	// Remove all existing menu items except the "None" item

	while ( [driverButton numberOfItems] > 1 )
		[driverButton removeItemAtIndex:1];
		
	// Walk through /dev, looking for either cu.* or tty.* items

	if ( (dir = opendir("/dev")) )
	{
		while ( (ent = readdir(dir)) )
		{
			// Device name must be at least 4 characters long to
			// do the following string comparisons..
			
			if ( ent->d_namlen >= 4 )
			{
				if ( (strncmp(ent->d_name, "cu.", 3) == 0) )
				{
					// Add item to serial driver menu
					
					if ( strcmp(ent->d_name, "cu.modem") == 0 )
					{
						// Built-in, GeeThree, or similar
						
						[driverButton addItemWithTitle:@"Built-In Serial"];
					}
					else if ( strncmp(ent->d_name, "cu.USA28X", 9) == 0
								|| strncmp(ent->d_name, "cu.KeySerial", 12) == 0 )
					{
						// Some sort of KeySpan driver
						
						int len = strlen(ent->d_name);
						
						if ( ent->d_name[len - 1] == '1' ) 
							[driverButton addItemWithTitle:@"KeySpan Port 1"];
						
						else if ( ent->d_name[len - 1] == '2' ) 
							[driverButton addItemWithTitle:@"KeySpan Port 2"];
							
						else
							[driverButton addItemWithTitle:@"Unknown KeySpan Port"];
					}
					else if ( strncmp(ent->d_name, "cu.usbserial", 12) == 0 )
					{
						// NewtUSB
						
						[driverButton addItemWithTitle:@"NewtUSB"];
					}
					else if ( strcmp(ent->d_name, "cu.Bluetooth-PDA-Sync") == 0 
								|| strcmp(ent->d_name, "cu.Bluetooth-Modem") == 0 )
					{
						// Hide these, they won't work
						
						continue;
					}
					else
					{
						// Don't know what this is, just show the raw device name
						
						[driverButton addItemWithTitle:[NSString stringWithCString:ent->d_name]];
					}
					
					// Associate device name with this menu item
					
					[[driverButton lastItem] setRepresentedObject:[NSString stringWithCString:ent->d_name]];
				}
			}
	
		}
		
		closedir(dir);
	}
}


- (IBAction)selectDriver:(id)sender
//
// Called when user selects an item from serial driver popup menu
//
{
	// If serial driver selected is not the "None" item, 
	// then enable the "Install Package" button

	BOOL enabled = ([driverButton indexOfSelectedItem] != 0); 
	[installPackageButton setEnabled:enabled];

	if ( enabled )
	{
		[[NSUserDefaults standardUserDefaults] 
							setObject:[[driverButton itemAtIndex:[driverButton indexOfSelectedItem]] 
							representedObject] forKey:@"PreferredPort"];
	}
	else
	{
		[[NSUserDefaults standardUserDefaults] removeObjectForKey:@"PreferredPort"];
	}

	[[NSUserDefaults standardUserDefaults] synchronize];
}


- (IBAction)selectPackage:(id)sender
//
// Called when user clicks on the button to select which package should
// be installed
//
{
	NSArray* fileTypes = [NSArray arrayWithObjects:@"pkg", @"PKG", @"Pkg", nil];
  
	// Display an "open file" sheet
  
	NSOpenPanel* openPanel = [NSOpenPanel openPanel];
	[openPanel setAllowsMultipleSelection:YES];

	[openPanel beginSheetForDirectory:nil
			file:nil 
			types:fileTypes 
			modalForWindow:mainWindow 
			modalDelegate:self 
			didEndSelector:@selector(packagePanelDidEnd:returnCode:contextInfo:) 
			contextInfo:self];
}


- (IBAction)showHelp:(id)sender
//
// User selected help menu item
//
{
	NSString* readMePath = [[NSBundle mainBundle] pathForResource:@"Instructions" ofType:@"rtf"];
	[[NSWorkspace sharedWorkspace] openFile:readMePath];
}


- (void)showInstallSheet
{
	[NSApp beginSheet:sheet modalForWindow:mainWindow modalDelegate:nil didEndSelector:nil contextInfo:nil];
}


/*
- (void)timeout:(NSTimer*)timer
{
	NSLog(@"timed out");
	NewtonConnection* connection = [timer userInfo];
	[connection cancel];
	
	giveUp = YES;
}
*/


- (void)updateProgress:(NSNumber*)current
//
// Update the installation progress bar
//
{
	[progress setDoubleValue:[current doubleValue]];
}


- (void)updateProgressMax:(NSNumber*)maximum
//
// Update the installation progress bar
//
{
	[progress setMinValue:0];
	[progress setMaxValue:[maximum doubleValue]];
}


- (void)updateStatus:(NSString*)statusText
//
// Update the installation status text
//
{
	[status setStringValue:statusText];
}


@end

