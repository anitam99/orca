//
//  ORIP320Model.cp
//  Orca
//
//  Created by Mark Howe on Mon Feb 10 2003.
//  Copyright � 2002 CENPA, University of Washington. All rights reserved.
//-----------------------------------------------------------
//This program was prepared for the Regents of the University of 
//Washington at the Center for Experimental Nuclear Physics and 
//Astrophysics (CENPA) sponsored in part by the United States 
//Department of Energy (DOE) under Grant #DE-FG02-97ER41020. 
//The University has certain rights in the program pursuant to 
//the contract and the program should not be copied or distributed 
//outside your organization.  The DOE and the University of 
//Washington reserve all rights in the program. Neither the authors,
//University of Washington, or U.S. Government make any warranty, 
//express or implied, or assume any liability or responsibility 
//for the use of this software.
//-------------------------------------------------------------


#pragma mark ���Imported Files
#import "ORIP320Model.h"
#import "ORIPCarrierModel.h"
#import "ORVmeCrateModel.h"
#import "ORDataTypeAssigner.h"
#import "ORTimer.h"

#import "ORIP320Channel.h"
#include <math.h>

#define KDelayTime .00005 //50 microsecond delay to allow for the 8.5 microsecond settling time of the input

#pragma mark ���Notification Strings
NSString* ORIP320ModelShipRecordsChanged			= @"ORIP320ModelShipRecordsChanged";
NSString* ORIP320ModelLogFileChanged				= @"ORIP320ModelLogFileChanged";
NSString* ORIP320ModelLogToFileChanged				= @"ORIP320ModelLogToFileChanged";
NSString* ORIP320ModelDisplayRawChanged				= @"ORIP320ModelDisplayRawChanged";
NSString* ORIP320GainChangedNotification			= @"ORIP320GainChangedNotification";
NSString* ORIP320ModeChangedNotification			= @"ORIP320ModeChangedNotification";
NSString* ORIP320AdcValueChangedNotification 		= @"ORIP320AdcValueChangedNotification";

NSString* ORIP320WriteValueChangedNotification		= @"IP320 WriteValue Changed Notification";
NSString* ORIP320ReadMaskChangedNotification 		= @"IP320 ReadMask Changed Notification";
NSString* ORIP320ReadValueChangedNotification		= @"IP320 ReadValue Changed Notification";
NSString* ORIP320PollingStateChangedNotification	= @"ORIP320PollingStateChangedNotification";
NSString* ORIP320ModelModeChanged					= @"ORIP320ModelModeChanged";


static struct {
    NSString* regName;
    unsigned long addressOffset;
}reg[kNum320Registers]={
	{@"Control Reg",  0x0000},
	{@"Convert Cmd",  0x0010},
	{@"ADC Data Reg", 0x0020},		
};

@interface ORIP320Model (private)
- (void) _setUpPolling:(BOOL)verbose;
- (void) _stopPolling;
- (void) _startPolling;
- (void) _pollAllChannels;
@end

@implementation ORIP320Model

#pragma mark ���Initialization
- (id) init //designated initializer
{
    self = [super init];
    [[self undoManager] disableUndoRegistration];
    [self setChanObjs:[NSMutableArray array]];
    int i=0;
    for(i=0;i<kNumIP320Channels;i++){
        [chanObjs addObject:[[[ORIP320Channel alloc] initWithAdc:self channel:i]autorelease]];
    }
	[self setCardJumperSetting:kUncalibrated];
    [[self undoManager] enableUndoRegistration];
    return self;
}

-(void)dealloc
{
    [logFile release];
	[self _stopPolling];
    [chanObjs release];
    [super dealloc];
}

- (void) wakeUp
{
    if(![self aWake]){
        [self _setUpPolling:NO];
		if(logToFile){
			[self performSelector:@selector(writeLogBufferToFile) withObject:nil afterDelay:60];		
		}
    }
    [super wakeUp];
}

- (void) sleep
{
    [super sleep];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

- (void) setUpImage
{
    [self setImage:[NSImage imageNamed:@"IP320"]];
}

- (void) makeMainController
{
    [self linkToController:@"ORIP320Controller"];
}



#pragma mark ���Accessors

- (BOOL) shipRecords
{
    return shipRecords;
}

- (void) setShipRecords:(BOOL)aShipRecords
{
    [[[self undoManager] prepareWithInvocationTarget:self] setShipRecords:shipRecords];
    
    shipRecords = aShipRecords;

    [[NSNotificationCenter defaultCenter] postNotificationName:ORIP320ModelShipRecordsChanged object:self];
}

- (NSString*) logFile
{
    return logFile;
}

- (void) setLogFile:(NSString*)aLogFile
{
    [[[self undoManager] prepareWithInvocationTarget:self] setLogFile:logFile];
				
    [logFile autorelease];
    logFile = [aLogFile copy];    

    [[NSNotificationCenter defaultCenter] postNotificationName:ORIP320ModelLogFileChanged object:self];
}

- (BOOL) logToFile
{
    return logToFile;
}

- (void) setLogToFile:(BOOL)aLogToFile
{
    [[[self undoManager] prepareWithInvocationTarget:self] setLogToFile:logToFile];
    
    logToFile = aLogToFile;
	
	if(logToFile)[self performSelector:@selector(writeLogBufferToFile) withObject:nil afterDelay:60];
	else [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(writeLogBufferToFile) object:nil];


    [[NSNotificationCenter defaultCenter] postNotificationName:ORIP320ModelLogToFileChanged object:self];
}

- (void) setMode:(int)aMode
{
    [[[self undoManager] prepareWithInvocationTarget:self] setMode:mode];
    
    mode = aMode;

    [[NSNotificationCenter defaultCenter] postNotificationName:ORIP320ModelModeChanged object:self];

}

- (int) mode
{
	return mode;
}

- (BOOL) displayRaw
{
    return displayRaw;
}

- (void) setDisplayRaw:(BOOL)aDisplayRaw
{
    [[[self undoManager] prepareWithInvocationTarget:self] setDisplayRaw:displayRaw];
    
    displayRaw = aDisplayRaw;

    [[NSNotificationCenter defaultCenter] postNotificationName:ORIP320ModelDisplayRawChanged object:self];
}

- (void) writeLogBufferToFile
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(writeLogBufferToFile) object:nil];
	if(logToFile && [logBuffer count] && [logFile length]){
		if(![[NSFileManager defaultManager] fileExistsAtPath:[logFile stringByExpandingTildeInPath]]){
			[[NSFileManager defaultManager] createFileAtPath:[logFile stringByExpandingTildeInPath] contents:nil attributes:nil];
		}
		
		NSFileHandle* fh = [NSFileHandle fileHandleForUpdatingAtPath:[logFile stringByExpandingTildeInPath]];
		int i;
		int n = [logBuffer count];
		for(i=0;i<n;i++){
			[fh writeData:[[logBuffer objectAtIndex:i] dataUsingEncoding:NSASCIIStringEncoding]];
		}
		[fh closeFile];
		[logBuffer removeAllObjects];
	}
	[self performSelector:@selector(writeLogBufferToFile) withObject:nil afterDelay:60];
}

- (void) setCardJumperSetting: (int)aCardJumperSetting
{
	int cardJumperSetting = aCardJumperSetting;
	int gain;
	for(gain=0;gain<knumGainSettings;gain++){CalibrationConstants[gain].kCardJumperSetting= aCardJumperSetting;}
	switch(cardJumperSetting)
	{
		case(kMinus5to5):
			NSLog(@"IP320 Card is set to -5 to 5 Volts\n");
			[self setCardCalibration];
			break;
		case(kMinus10to10):
			NSLog(@"IP320 Card is set to -10 to 10 Volts\n");
			[self setCardCalibration];
			break;
		case(k0to10):
			NSLog(@"IP320 Card is set to 0 to 10 Volts\n");
			[self setCardCalibration];
			break;
		case(kUncalibrated):
			NSLog(@"IP320 Card is uncalibrated\n");
			[self setCardCalibration];
			break;
	}

}

- (void) setCardCalibration
{
	int countergain=0;
	int cardJumperSetting=CalibrationConstants[0].kCardJumperSetting;
	switch(cardJumperSetting){
		case(kMinus5to5):
			NSLog(@"Calibrating IP320 for -5 to 5 Voltage Range\n");
			
			for(countergain=0;countergain<knumGainSettings;countergain++)
			{
				CalibrationConstants[countergain].kIdeal_Volt_Span=10.000;
				CalibrationConstants[countergain].kIdeal_Zero=-5.0000;
			}
			[self callibrateIP320];
			break;
		case(kMinus10to10):
			NSLog(@"Calibrating IP320 for -10 to 10 Voltage Range\n");

			for(countergain=0;countergain<knumGainSettings;countergain++){
				CalibrationConstants[countergain].kIdeal_Volt_Span=20.000;
				CalibrationConstants[countergain].kIdeal_Zero=-10.0000;
			}
			[self callibrateIP320];
			break;
		case(k0to10):
			NSLog(@"Calibrating IP320 for 0 to 10 Voltage Range\n");
			for(countergain=0;countergain<knumGainSettings;countergain++){
				CalibrationConstants[countergain].kIdeal_Volt_Span=10.000;
				CalibrationConstants[countergain].kIdeal_Zero=0.0000;
				
			}
			[self callibrateIP320];
			break;
		case(kUncalibrated):
			NSLog(@"IP320 returns uncorrected value.\n");
			break;
	}
}





// ===========================================================
// - chanObjs:
// ===========================================================
- (NSMutableArray *)chanObjs
{
    return chanObjs; 
}

// ===========================================================
// - setChanObjs:
// ===========================================================
- (void)setChanObjs:(NSMutableArray *)aChanArray 
{
    [aChanArray retain];
    [chanObjs release];
    chanObjs = aChanArray;
}


- (unsigned long) dataId { return dataId; }
- (void) setDataId: (unsigned long) DataId
{
    dataId = DataId;
}

- (void) setPollingState:(NSTimeInterval)aState
{
    [[[self undoManager] prepareWithInvocationTarget:self] setPollingState:pollingState];
    
    pollingState = aState;
    
    [self performSelector:@selector(_startPolling) withObject:nil afterDelay:0.5];
    
    [[NSNotificationCenter defaultCenter]
		postNotificationName:ORIP320PollingStateChangedNotification
                      object: self];
    
}

- (void) postNotification:(NSNotification*)aNote
{
	[[NSNotificationCenter defaultCenter] postNotification:aNote];
}

- (NSTimeInterval)	pollingState
{
    return pollingState;
}
- (BOOL) hasBeenPolled 
{ 
    return hasBeenPolled;
}

#pragma mark ���Hardware Access
- (unsigned long) getRegisterAddress:(short) aRegister
{
    int ip = [self slotConv];
    return [guardian baseAddress] + ip*0x100 + reg[aRegister].addressOffset;
}

- (unsigned long) getAddressOffset:(short) anIndex
{
    return reg[anIndex].addressOffset;
}

- (NSString*) getRegisterName:(short) anIndex
{
    return reg[anIndex].regName;
}

- (short) getNumRegisters;
{
    return kNum320Registers;
}

- (void) loadConstants:(unsigned short)aChannel
{
    ORIP320Channel* chanObj = [chanObjs objectAtIndex:aChannel];
    unsigned short aMask = 0;
    aMask |= (aChannel%20 & kChan_mask);//bits 0-5
	aMask |= [chanObj gain] << 6;       //bits 6-7
	aMask |= [self mode] << 8;			//bits 8-9
        
	[[guardian adapter] writeWordBlock:&aMask
								 atAddress:[self getRegisterAddress:kControlReg]
								numToWrite:1L
								withAddMod:[guardian addressModifier]
							 usingAddSpace:kAccessRemoteIO];
}

- (void) loadConversionStart
{
			unsigned short modifier = [guardian addressModifier];
			unsigned short dummyValue = 0xFFFF;
			id cachedController = [guardian adapter];
			[cachedController writeWordBlock:&dummyValue
									 atAddress:[self getRegisterAddress:kConvertCmd]
									numToWrite:1L
									withAddMod:modifier
								 usingAddSpace:kAccessRemoteIO];


}

-(unsigned short) readDataBlock
{	
	unsigned short value = 0;
	unsigned short modifier = [guardian addressModifier];
	id cachedController = [guardian adapter];
	[cachedController readWordBlock:(unsigned short*)&value
									atAddress:[self getRegisterAddress:kControlReg]
									numToRead:1L
								   withAddMod:modifier
								usingAddSpace:kAccessRemoteIO];


			
	 if((value & 0x8000) == 0x8000){
			[cachedController readWordBlock:(unsigned short*)&value
									atAddress:[self getRegisterAddress:kADCDataReg]
									numToRead:1L
								withAddMod:modifier
								usingAddSpace:kAccessRemoteIO];
			
				//the value needs to be shifted by 4 bits after the read. That's how is comes off the card....
			value=((value>>4) & 0x0fff);
	}
	return value;
}

- (unsigned short) readAdcChannel:(unsigned short)aChannel//Brandon's Version
{
	int changeCount = 0;
	unsigned short value = 0;
	unsigned short corrected_value = 0;
	@synchronized(self) {
		NSString* errorLocation = @"";
		NS_DURING
			errorLocation = @"Control Reg Setup";
			[self loadConstants:aChannel];
			[ORTimer delay:KDelayTime];

			errorLocation = @"Converion Start";
			[self loadConversionStart];
			errorLocation = @"Adc Read";
			value = [self readDataBlock];
			corrected_value = [self calculateCorrectedCount:[[chanObjs objectAtIndex:aChannel] gain] countActual:value];
			if([[chanObjs objectAtIndex:aChannel] setChannelValue:corrected_value])changeCount++;
		NS_HANDLER
			NSLogError(@"",[NSString stringWithFormat:@"IP320 %d,%@",[self slot],[self identifier]],errorLocation,nil);
			[NSException raise:[NSString stringWithFormat:@"IP320 Read Adc Channel %d Failed",aChannel] format:@"Error Location: %@",errorLocation];
		NS_ENDHANDLER
		if(changeCount){
			[self performSelectorOnMainThread:@selector(postNotification:) withObject:[NSNotification notificationWithName:ORIP320AdcValueChangedNotification object:self] waitUntilDone:NO];
		}
	}
//	NSLog(@"the corected value is %d\n",[self calculateCorrectedCount:[[chanObjs objectAtIndex:aChannel] gain] countActual:value]);
	return corrected_value;
}

//Calibration routines
- (void) loadCALHIControReg:(unsigned short)gain{
	int cardJumperSetting=CalibrationConstants[0].kCardJumperSetting;
	unsigned short aMaskCALHI = 0x0000;
	if((cardJumperSetting==kMinus5to5&&gain==0)||(cardJumperSetting==kMinus10to10&&gain<=1)||(cardJumperSetting==k0to10&&gain<=1)){
		CalibrationConstants[gain].kVoltCALHI=kCAL0_volt;
		aMaskCALHI|=kCAL0_mask;
		aMaskCALHI|=(gain<<6);	
	}
	else if((cardJumperSetting==kMinus5to5&&gain==1)||(cardJumperSetting==kMinus10to10&&gain==2)||(cardJumperSetting==k0to10&&gain==2)){
		CalibrationConstants[gain].kVoltCALHI=kCAL1_volt;
		aMaskCALHI|=kCAL1_mask;
		aMaskCALHI|=(gain<<6);	
	}
	else if((cardJumperSetting==kMinus5to5&&gain==2)||(cardJumperSetting==kMinus10to10&&gain==3)||(cardJumperSetting==k0to10&&gain==3)){
		CalibrationConstants[gain].kVoltCALHI=kCAL2_volt;
		aMaskCALHI|=kCAL2_mask;
		aMaskCALHI|=(gain<<6);	
	}
	else if(cardJumperSetting==kMinus5to5&&gain==3){
		CalibrationConstants[gain].kVoltCALHI=kCAL3_volt;
		aMaskCALHI|=kCAL3_mask;
		aMaskCALHI|=(gain<<6);	
	}
	[[guardian adapter] writeWordBlock:&aMaskCALHI
								atAddress:[self getRegisterAddress:kControlReg]
								numToWrite:1L
								withAddMod:[guardian addressModifier]
								usingAddSpace:kAccessRemoteIO];
	

}

- (void) loadCALLOControReg:(unsigned short)gain
{
	unsigned short aMaskCALLO = 0;
	int cardJumperSetting=CalibrationConstants[0].kCardJumperSetting;

//Find CountCALLO
	if(cardJumperSetting==k0to10){
			CalibrationConstants[gain].kVoltCALLO=kCAL3_volt;
			aMaskCALLO|=kCAL3_mask;
			aMaskCALLO|=(gain<<6);
	}
	else {
		CalibrationConstants[gain].kVoltCALLO=kAUTOZERO_volt;
		aMaskCALLO|=kAUTOZERO_mask;
		aMaskCALLO|=(gain<<6);
		
	}
	[[guardian adapter] writeWordBlock:&aMaskCALLO
								atAddress:[self getRegisterAddress:kControlReg]
								numToWrite:1L
								withAddMod:[guardian addressModifier]
								usingAddSpace:kAccessRemoteIO];
}

-(void) calculateCalibrationSlope:(unsigned short)gain
{ 
	float slope;
	slope=pow(2,gain)*(CalibrationConstants[gain].kVoltCALHI-CalibrationConstants[gain].kVoltCALLO)/(CalibrationConstants[gain].kCountCALHI-CalibrationConstants[gain].kCountCALLO);
	CalibrationConstants[gain].kSlope_m=slope;
}

-(unsigned short) calculateCorrectedCount:(unsigned short)gain countActual:(unsigned short)countActual
{
	unsigned short corrected_count;
	int cardJumperSetting=CalibrationConstants[0].kCardJumperSetting;

	if(cardJumperSetting==kUncalibrated) { corrected_count=countActual; }
	else {
		corrected_count=countActual;
		corrected_count+=((CalibrationConstants[gain].kVoltCALLO*pow(2,gain))-CalibrationConstants[gain].kIdeal_Zero)/CalibrationConstants[gain].kSlope_m;
		corrected_count= corrected_count-CalibrationConstants[gain].kCountCALLO;
		corrected_count=corrected_count*(4096*CalibrationConstants[gain].kSlope_m)/CalibrationConstants[gain].kIdeal_Volt_Span;
	}
	return corrected_count;
	
}
- (void) callibrateIP320
{
		int gain =0;
		unsigned short ReadNumber = 10;
		@synchronized(self) {
		NSString* errorLocation = @"";
		NS_DURING
			for(gain=0;gain<=3;gain++){
				
				errorLocation = @"CountCALHI Control Reg Setup";
				[self loadCALHIControReg:gain];
				[ORTimer delay:0.01];
				unsigned short CountCALHI=0;
				int i=0;
				for(i=0;i<ReadNumber;i++){
					errorLocation = @"CountCALHI Converion Start";
					[self loadConversionStart];
					errorLocation = @"CountCALHI Adc Read";
					CountCALHI+=[self readDataBlock];
				}
				CountCALHI=CountCALHI/ReadNumber;
				CalibrationConstants[gain].kCountCALHI=CountCALHI;
				
				errorLocation = @"CountCALLO Control Reg Setup";
				[self loadCALLOControReg:gain];
				[ORTimer delay:KDelayTime];

				unsigned short CountCALLO=0;
				for(i=0;i<ReadNumber;i++){
					errorLocation = @"CountCALLO Converion Start";
					[self loadConversionStart];
					errorLocation = @"CountCALLO Adc Read";
					CountCALLO+=[self readDataBlock];
				}
				CountCALLO=CountCALLO/ReadNumber;
				CalibrationConstants[gain].kCountCALLO=CountCALLO;
				[self calculateCalibrationSlope:gain];
				
				NSLog(@"Calibraton Slope at gain %f is %f\n",pow(2,gain),CalibrationConstants[gain].kSlope_m);
			}
			
			
		NS_HANDLER
			NSLogError(@"",[NSString stringWithFormat:@"IP320 %d,%@",[self slot],[self identifier]],errorLocation,nil);
			[NSException raise:[NSString stringWithFormat:@"IP320 Calibration Failed"] format:@"Error Location: %@",errorLocation];
		NS_ENDHANDLER
	}

}

- (void) readAllAdcChannels
{
	@synchronized(self) {
		NSString*   outputString = nil;
		if(logToFile) {
			//get the time(UT!)
			time_t		theTime;
			time(&theTime);
			struct tm* theTimeGMTAsStruct = gmtime(&theTime);
			time_t ut_time = mktime(theTimeGMTAsStruct);
			outputString = [NSString stringWithFormat:@"%u ",ut_time];
		}

		short chan;
		for(chan=0;chan<kNumIP320Channels;chan++){
			if([[chanObjs objectAtIndex:chan] readEnabled]){
				if(mode == 0 && chan>=20)break;	//if differential, don't read chan >= 20
				[self readAdcChannel:chan];
				if(logToFile)outputString = [outputString stringByAppendingFormat:@"%6.3f ",[self convertedValue:chan]];
			}
			else if(logToFile) outputString = [outputString stringByAppendingString:@"0 "];
		}
		
		if(logToFile){
			outputString = [outputString stringByAppendingString:@"\n"];
			//accumulate into a buffer, we'll write the file later
			if(!logBuffer)logBuffer = [[NSMutableArray arrayWithCapacity:1024] retain];
			if([outputString length]){
				[logBuffer addObject:outputString];
			}
		}
		
		readCount++;		
	}
}



- (void) _pollAllChannels
{
    NS_DURING 
        [self readAllAdcChannels]; 
		if(shipRecords){
			[self shipValues]; 
		}
    NS_HANDLER 
	//catch this here to prevent it from falling thru, but nothing to do.
	NS_ENDHANDLER
        
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_pollAllChannels) object:nil];
	if(pollingState!=0){
		[self performSelector:@selector(_pollAllChannels) withObject:nil afterDelay:pollingState];
	}
}

- (void) enablePollAll:(BOOL)state
{
    short chan;
    for(chan=0;chan<kNumIP320Channels;chan++){
        [[chanObjs objectAtIndex:chan] setObject:[NSNumber numberWithBool:state] forKey:k320ChannelReadEnabled];
    }
}

- (void) enableAlarmAll:(BOOL)state
{
    short chan;
    for(chan=0;chan<kNumIP320Channels;chan++){
        [[chanObjs objectAtIndex:chan] setObject:[NSNumber numberWithBool:state] forKey:k320ChannelAlarmEnabled];
    }
}


#pragma mark ���Polling
- (void) _stopPolling
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_pollAllChannels) object:nil];
	pollRunning = NO;
}

- (void) _startPolling
{
	[self _setUpPolling:YES];
}

- (void) _setUpPolling:(BOOL)verbose
{

	if(pollRunning)return;
	
    if(pollingState!=0){  
		readCount = 0;
		pollRunning = YES;
        if(verbose)NSLog(@"Polling IP320,%d,%d,%d  every %.0f seconds.\n",[self crateNumber],[self slot],[self slotConv],pollingState);
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_pollAllChannels) object:nil];
        [self performSelector:@selector(_pollAllChannels) withObject:self afterDelay:pollingState];
        [self _pollAllChannels];
    }
    else {
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_pollAllChannels) object:nil];
        if(verbose)NSLog(@"Not Polling IP320,%d,%d,%d\n",[self crateNumber],[self slot],[self slotConv]);
    }
}

#pragma mark ���Archival
static NSString* kORIP320chanObjs   = @"kORIP320chanObjs";
static NSString *kORIP320PollingState   = @"kORIP320PollingState";

- (id)initWithCoder:(NSCoder*)decoder
{
    self = [super initWithCoder:decoder];
	    
    [[self undoManager] disableUndoRegistration];
    [self setShipRecords:[decoder decodeBoolForKey:@"ORIP320ModelShipRecords"]];
    [self setLogFile:[decoder decodeObjectForKey:@"ORIP320ModelLogFile"]];
    [self setLogToFile:[decoder decodeBoolForKey:@"ORIP320ModelLogToFile"]];
    [self setDisplayRaw:[decoder decodeBoolForKey:@"ORIP320ModelDisplayRaw"]];
    [self setChanObjs:[decoder decodeObjectForKey:kORIP320chanObjs]];
	//[self setCardJumperSetting:[decoder decodeIntForKey:@"ORIP320ModelsetCardJumpertSetting"]];
    [self setCardJumperSetting:kUncalibrated];
	[self setPollingState:[decoder decodeIntForKey:kORIP320PollingState]];
	[[self undoManager] enableUndoRegistration];
    
    
    if(chanObjs == nil){
        [self setChanObjs:[NSMutableArray array]];
        int i;
        for(i=0;i<kNumIP320Channels;i++){
            [chanObjs addObject:[[[ORIP320Channel alloc] initWithAdc:self channel:i]autorelease]];
        }
    }
	[chanObjs makeObjectsPerformSelector:@selector(setAdcCard:) withObject:self];
	   	
    return self;
}

- (void)encodeWithCoder:(NSCoder*)encoder
{
    [super encodeWithCoder:encoder];
    [encoder encodeBool:shipRecords forKey:@"ORIP320ModelShipRecords"];
    [encoder encodeObject:logFile forKey:@"ORIP320ModelLogFile"];
    [encoder encodeBool:logToFile forKey:@"ORIP320ModelLogToFile"];
    [encoder encodeBool:displayRaw forKey:@"ORIP320ModelDisplayRaw"];
    [encoder encodeObject:chanObjs forKey:kORIP320chanObjs];
    [encoder encodeInt:[self pollingState] forKey:kORIP320PollingState];
//	[encoder encodeInt:CalibrationConstants[0].kCardJumperSetting forKey:@"ORIP320ModelsetCardJumpertSetting"];
}

#pragma mark ���Bit Processing Protocol
- (void)processIsStarting
{
}

- (void)processIsStopping
{
}
//note that everything called by these routines MUST be threadsafe
- (void) startProcessCycle
{
	//let the polling stay in the polling loop....
   // [self readAllAdcChannels];
}

- (void) endProcessCycle
{
    //nothing to do
}

- (int) processValue:(int)channel
{
	return 0;
}

- (void) setProcessOutput:(int)channel value:(int)value
{
    //nothing to do
}

- (NSString*) processingTitle
{
    return [NSString stringWithFormat:@"%d,%d,%@",[self crateNumber],[guardian slot],[self identifier]];
}

- (double) convertedValue:(int)channel
{
	return [[[chanObjs objectAtIndex:channel] objectForKey:k320ChannelValue] doubleValue];
}

- (double) maxValueForChan:(int)channel
{
	double theMax = 0;
	@synchronized(self){
		theMax =  [[chanObjs objectAtIndex:channel] maxValue];
	}
	return theMax;
}
- (double) minValueForChan:(int)channel
{
	return 0;
}
- (void) getAlarmRangeLow:(double*)theLowLimit high:(double*)theHighLimit channel:(int)channel
{
	@synchronized(self){
		*theLowLimit = [[[chanObjs objectAtIndex:channel] objectForKey:k320ChannelLowValue] doubleValue];
		*theHighLimit = [[[chanObjs objectAtIndex:channel] objectForKey:k320ChannelHighValue] doubleValue];
	}		
}

- (unsigned long) lowMask
{
	int i;
	unsigned long aMask = 0;
	for(i=0;i<32;i++){
		if([[chanObjs objectAtIndex:i] readEnabled]){
			aMask |= 1L<<i;
		}
	}
	return aMask;
}

- (unsigned long) highMask
{
	unsigned long aMask = 0;
	int i;
	for(i=0;i<8;i++){
		if([[chanObjs objectAtIndex:i+32] readEnabled]){
			aMask |= 1L<<i;
		}
	}
	return aMask;
}

#pragma mark ���Data Records

- (void) setDataIds:(id)assigner
{
    dataId       = [assigner assignDataIds:kLongForm]; //short form preferred
}

- (void) syncDataIdsWith:(id)anotherCard
{
    [self setDataId:[anotherCard dataId]];
}

- (NSMutableDictionary*) addParametersToDictionary:(NSMutableDictionary*)dictionary
{
    NSMutableDictionary* objDictionary = [super addParametersToDictionary:dictionary];
	int i;
	for(i=0;i<kNumIP320Channels;i++){
		[objDictionary setObject:[[chanObjs objectAtIndex:i] parameters] forKey:[NSString stringWithFormat:@"chan%d",i]];
	}	
	return objDictionary;
}

- (void) appendDataDescription:(ORDataPacket*)aDataPacket userInfo:(id)userInfo
{
    [aDataPacket addDataDescriptionItem:[self dataRecordDescription] forKey:@"IP320"];
}

- (NSDictionary*) dataRecordDescription
{
    NSMutableDictionary* dataDictionary = [NSMutableDictionary dictionary];
    NSDictionary* aDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
        @"ORIP320DecoderForAdc",						@"decoder",
        [NSNumber numberWithLong:dataId],               @"dataId",
        [NSNumber numberWithBool:YES],                  @"variable",
        [NSNumber numberWithLong:-1],					@"length",
        nil];
    [dataDictionary setObject:aDictionary forKey:@"IP320ADC"];
    
    return dataDictionary;
}


-(void) shipValues
{
    BOOL runInProgress = [gOrcaGlobals runInProgress];

	if(runInProgress){
		unsigned long data[43];
		
		data[1] = (([self crateNumber]&0x01e)<<21) | ([guardian slot]& 0x0000001f)<<16 | ([self slot]&0xf);
		
		//get the time(UT!)
		time_t	theTime;
		time(&theTime);
		struct tm* theTimeGMTAsStruct = gmtime(&theTime);
		time_t ut_time = mktime(theTimeGMTAsStruct);
		data[2] = ut_time;	//seconds since 1970
		
		int index = 3;
		int i;
		int n;
		if(mode == 0) n = 20;
		else n = 40;
		for(i=0;i<n;i++){
			if([[chanObjs objectAtIndex:i] readEnabled]){
				int val  = [[chanObjs objectAtIndex:i] rawValue];
				data[index++] = (i&0xff)<<16 | val & 0xfff;
			}
		}
		data[0] = dataId | index;
		
		if(index>3){
			[[NSNotificationCenter defaultCenter] postNotificationName:ORQueueRecordForShippingNotification 
														object:[NSData dataWithBytes:data length:index*sizeof(long)]];
		}
	}
}


@end
