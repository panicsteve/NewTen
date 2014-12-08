#import "NewtonConnection.h"

//
// Based on UnixNPI by
// Richard C.I. Li, Chayim I. Kirshen, Victor Rehorst
// Objective-C adaptation by Steven Frank <stevenf@panic.com>
//

@interface NewtonConnection (Private)

- (id)initWithDevicePath:(NSString*)devicePath speed:(int)speed;
- (void)calculateFCSWithWords:(unsigned short*)fcsWord octet:(unsigned char)octet;

@end


@implementation NewtonConnection

+ (NewtonConnection*)connectionWithDevicePath:(NSString*)devicePath speed:(int)speed
{
	return [[[NewtonConnection alloc] initWithDevicePath:devicePath speed:speed] autorelease];
}


- (id)initWithDevicePath:(NSString*)devicePath speed:(int)speed
{
	if ( (self = [super init]) )
	{
		canceled = NO;
		
		// Initialize re-usable frame structures
		
		frameStart[0] = '\x16';
		frameStart[1] = '\x10';
		frameStart[2] = '\x02';
		
		frameEnd[0] = '\x10';
		frameEnd[1] = '\x03';

		ldFrame[0] = '\x04';	// Length of header 
		ldFrame[1] = '\x02',	// Type indication LD frame 
		ldFrame[2] = '\x01';
		ldFrame[3] = '\x01';
		ldFrame[4] = '\xff';

		// Open the serial port
		
		if ( (newtFD = open([devicePath fileSystemRepresentation], O_RDWR)) == -1 )
		{
			[self release];
			return nil;
		}
		
		// Get the current device settings 
		
		tcgetattr(newtFD, &newtTTY);
		
		// Change the device settings 
		
		newtTTY.c_iflag = IGNBRK | INPCK;
		newtTTY.c_oflag = 0;
		newtTTY.c_cflag = (CREAD | CLOCAL | CS8) & ~PARENB & ~PARODD & ~CSTOPB;
		newtTTY.c_lflag = 0;
		newtTTY.c_cc[VMIN] = 1;
		newtTTY.c_cc[VTIME] = 0;
		
		// Select the communication speed 
		
		switch ( speed ) 
		{
			case 2400 :
				cfsetospeed(&newtTTY, B2400);
				cfsetispeed(&newtTTY, B2400);
				break;

			case 4800 :
				cfsetospeed(&newtTTY, B4800);
				cfsetispeed(&newtTTY, B4800);
				break;

			case 9600 :
				cfsetospeed(&newtTTY, B9600);
				cfsetispeed(&newtTTY, B9600);
				break;

			case 19200 :
				cfsetospeed(&newtTTY, B19200);
				cfsetispeed(&newtTTY, B19200);
				break;

			case 38400 :
				cfsetospeed(&newtTTY, B38400);
				cfsetispeed(&newtTTY, B38400);
				break;

			case 57600 :
				cfsetospeed(&newtTTY, B57600);
				cfsetispeed(&newtTTY, B57600);
				break;

			case 115200 :
				cfsetospeed(&newtTTY, B115200);
				cfsetispeed(&newtTTY, B115200);
				break;

			case 230400 :
				cfsetospeed(&newtTTY, B230400);
				cfsetispeed(&newtTTY, B230400);
				break;

			default :
				cfsetospeed(&newtTTY, B38400);
				cfsetispeed(&newtTTY, B38400);
				break;
		}
		
		// Flush the device and restart input and output 
		
		tcflush(newtFD, TCIOFLUSH);
		tcflow(newtFD, TCOON);
		
		// Update the new device settings 
		
		tcsetattr(newtFD, TCSANOW, &newtTTY);
	}
	
	return self;
}


- (void)dealloc
{
	// Close the serial port
	
	if ( newtFD >= 0 )
		close(newtFD);
	
	[super dealloc];
}


- (void)calculateFCSWithWords:(unsigned short*)fcsWord octet:(unsigned char)octet
//
// Calculate frame checksum
//
{
	int i;
	unsigned char pow = 1;

	for ( i = 0; i < 8; i++ ) 
	{
		if ( (((*fcsWord % 256) & 0x01) == 0x01) ^ ((octet & pow) == pow) )
			*fcsWord = (*fcsWord / 2) ^ 0xa001;
		else
			*fcsWord /= 2;

		pow *= 2;
	}
}


- (void)cancel
{
	canceled = YES;
}


- (void)disconnect
{	
	if ( newtFD >= 0 ) 
	{
		// Wait for all buffer sent 
		
		tcdrain(newtFD);
		[self sendFrame:NULL header:ldFrame length:0];
	}
	
	//ErrHandler("User interrupted, connection stopped!!");
}


- (int)receiveFrame:(unsigned char*)frame
{
	//char errMesg[] = "Error in reading from Newton device, connection stopped!!";
	int state;
	unsigned char buf;
	unsigned short fcsWord = 0;
	int i = 0;
	fd_set fds;
	struct timeval timeout = { 1, 0 };
		
	// Wait for head 
	
	state = 0;
	
	while ( state < 3 ) 
	{
		FD_ZERO(&fds);
		FD_SET(newtFD, &fds);

		if ( select(newtFD + 1, &fds, NULL, NULL, &timeout) < 1 )
			return -1;
		
		if ( read(newtFD, &buf, 1) < 0 )
			return -1; //ErrHandler(errMesg);

		switch ( state ) 
		{
			case 0 :
				if ( buf == frameStart[0] )
					++state;
				break;
				
			case 1 :
				if ( buf == frameStart[1] )
					++state;
				else
					state = 0;
				break;
				
			case 2:
				if ( buf == frameStart[2] )
					++state;
				else
					state = 0;
				break;
		}
	}
	
	// Wait for tail 
	
	state = 0;
	
	while ( state < 2 ) 
	{
		if ( read(newtFD, &buf, 1) < 0 )
			return -1; //ErrHandler(errMesg);
			
		switch ( state ) 
		{
			case 0 :
				if ( buf == '\x10' )
					++state;
				else 
				{
					[self calculateFCSWithWords:&fcsWord octet:buf];
					
					if ( i < MAX_HEAD_LEN + MAX_INFO_LEN ) 
					{
						frame[i] = buf;
						++i;
					}
					else
						return -1;
				}
				break;
				
			case 1 :
				if ( buf == '\x10' ) 
				{
					[self calculateFCSWithWords:&fcsWord octet:buf];

					if ( i < MAX_HEAD_LEN + MAX_INFO_LEN ) 
					{
						frame[i] = buf;
						++i;
					}
					else
						return -1;
						
					state = 0;
				}
				else 
				{
					if ( buf == '\x03' ) 
					{
						[self calculateFCSWithWords:&fcsWord octet:buf];
						++state;
					}
					else
						return -1;
				}
				break;
			}
		}
		
	// Check FCS 
	
	if ( read(newtFD, &buf, 1) < 0 )
		return -1; //ErrHandler(errMesg);
		
	if ( fcsWord % 256 != buf )
		return -1;

	if ( read(newtFD, &buf, 1) < 0 )
		return -1; //ErrHandler(errMesg);

	if ( fcsWord / 256 != buf )
		return -1;

	if ( frame[1] == '\x02' )
		return -1;//ErrHandler("Newton device disconnected, connection stopped!!");
		
	return 0;
}


- (BOOL)sendFrame:(unsigned char*)info header:(unsigned char*)head length:(int)infoLen
{
	//char errMesg[] = "Error in writing to Newton device, connection stopped!!";
	unsigned short fcsWord = 0;
	unsigned char buf;
	int i;
	
	// Send frame start 

	if ( write(newtFD, frameStart, 3) < 0 )
		return NO;
	
	// Send frame head 
	
	for ( i = 0; i <= head[0]; i++ ) 
	{
		[self calculateFCSWithWords:&fcsWord octet:head[i]];
		
		if ( write(newtFD, &head[i], 1) < 0 )
			return NO;
			
		if ( head[i] == frameEnd[0] ) 
		{
			if ( write(newtFD, &head[i], 1) < 0 )
				return NO;
		}
	}
	
	// Send frame information 
	
	if ( info != NULL ) 
	{
		for ( i = 0; i < infoLen; i++ ) 
		{
			[self calculateFCSWithWords:&fcsWord octet:info[i]];
		
			if ( write(newtFD, &info[i], 1) < 0 )
				return NO;
			
			if ( info[i] == frameEnd[0] ) 
			{
				if ( write(newtFD, &info[i], 1) < 0 )
					return NO;
			}
		}
	}

	// Send frame end 

	if ( write(newtFD, frameEnd, 2) < 0 )
		return NO;
		
	[self calculateFCSWithWords:&fcsWord octet:frameEnd[1]];

	// Send FCS 
	
	buf = fcsWord % 256;
	
	if ( write(newtFD, &buf, 1) < 0 )
		return NO;
		
	buf = fcsWord / 256;
	
	if ( write(newtFD, &buf, 1) < 0 )
		return NO;
		
	return YES;
}


- (void)sendLAFrame:(unsigned char)seqNo
{
	unsigned char laFrameHead[4] = 
	{
		'\x03', // Length of header 
		'\x05', // Type indication LA frame 
		'\x00', // Sequence number 
		'\x01'	// N(k) = 1 
	};

	laFrameHead[2] = seqNo;
	[self sendFrame:NULL header:laFrameHead length:0];
}


- (void)sendLTFrame:(unsigned char*)info length:(int)infoLen seqNo:(unsigned char)seqNo
{
	unsigned char ltFrameHead[3] = 
	{
		'\x02', // Length of header 
		'\x04', // Type indication LT frame 
	};
	
	ltFrameHead[2] = seqNo;
	[self sendFrame:info header:ltFrameHead length:infoLen];
}


- (int)waitForLAFrame:(unsigned char)seqNo
{
	unsigned char frame[MAX_HEAD_LEN + MAX_INFO_LEN];

	do 
	{
		while ( [self receiveFrame:frame] < 0 )
		{
			if ( canceled )
				break;
		}
		
		if ( canceled )
			break;
		
		if ( frame[1] == '\x04' )
			[self sendLAFrame:frame[2]];
	} 
	while ( frame[1] != '\x05' );
	
	if ( frame[2] == seqNo )
		return 0;
	else
		return -1;
}


- (int)waitForLDFrame
{
	//char errMesg[] = "Error in reading from Newton device, connection stopped!!";
	int state;
	unsigned char buf;
	unsigned short fcsWord = 0;
		
	// Wait for head 

	state = 0;

	while ( state < 5 )
	{
		if ( read(newtFD, &buf, 1) < 0 )
			return -1;//ErrHandler(errMesg);

		switch ( state ) 
		{
			case 0 :
				if ( buf == frameStart[0] )
					++state;
				break;
				
			case 1 :
				if ( buf == frameStart[1] )
					++state;
				else
					state = 0;
				break;
				
			case 2 :
				if ( buf == frameStart[2] )
					++state;
				else
					state = 0;
				break;
				
			case 3 :
				[self calculateFCSWithWords:&fcsWord octet:buf];
				++state;
				break;
				
			case 4 :
				if ( buf == '\x02' ) 
				{
					[self calculateFCSWithWords:&fcsWord octet:buf];
					++state;
				}
				else 
				{
					state = 0;
					fcsWord = 0;
				}
				break;
		}
	}
	
	// Wait for tail 

	state = 0;

	while ( state < 2 ) 
	{
		if ( read(newtFD, &buf, 1) < 0 )
			return -1;//ErrHandler(errMesg);

		switch ( state ) 
		{
			case 0 :
				if ( buf == '\x10' )
					++state;
				else
					[self calculateFCSWithWords:&fcsWord octet:buf];
				break;
				
			case 1 :
				if ( buf == '\x10' ) 
				{
					[self calculateFCSWithWords:&fcsWord octet:buf];
					state = 0;
				}
				else 
				{
					if ( buf == '\x03' ) 
					{
						[self calculateFCSWithWords:&fcsWord octet:buf];
						++state;
					}
					else
						return -1;
				}
				break;
		}
	}
		
	// Check FCS 

	if ( read(newtFD, &buf, 1) < 0 )
		return -1;//ErrHandler(errMesg);

	if ( fcsWord % 256 != buf )
		return -1;

	if ( read(newtFD, &buf, 1) < 0 )
		return -1; //ErrHandler(errMesg);

	if ( fcsWord / 256 != buf )
		return -1;

	return 0;
}

@end
