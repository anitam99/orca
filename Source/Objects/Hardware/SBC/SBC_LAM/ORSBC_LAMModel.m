//--------------------------------------------------------
// ORSBC_LAMModel
// Created by Mark  A. Howe on Mon Aug 23 2004
// Code partially generated by the OrcaCodeWizard. Written by Mark A. Howe.
// Copyright (c) 2004 CENPA, University of Washington. All rights reserved.
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

#pragma mark ***Imported Files


#import "ORSBC_LAMModel.h"

#import "ORReadOutList.h"
#import "ORLAMhosting.h"
#import "VME_HW_Definitions.h"

#pragma mark •••Notification Strings
NSString* ORSBC_LAMSlotChangedNotification	= @"ORSBC_LAMSlotChangedNotification";
NSString* ORSBC_LAMLock						= @"ORSBC_LAMLock";

@implementation ORSBC_LAMModel
- (id) init
{
	self = [super init];
    ORReadOutList* r1 = [[ORReadOutList alloc] initWithIdentifier:@"Readout"];
    [self setReadoutGroup:r1];
    [self setVariableNames:[NSMutableArray array]];
    [r1 release];
	return self;
}

- (void) dealloc
{
    [readoutGroup release];
    [variableNames release];
	[super dealloc];
}

- (void) setUpImage
{
	[self setImage:[NSImage imageNamed:@"SBC_LAM"]];
}

- (void) makeMainController
{
	[self linkToController:@"ORSBC_LAMController"];
}


#pragma mark ***Accessors
- (NSString*) cardSlotChangedNotification
{
    return ORSBC_LAMSlotChangedNotification;
}

- (BOOL) acceptsGuardian: (OrcaObject *)aGuardian
{
    //return [aGuardian isKindOfClass:NSClassFromString(@"SBC_Link")];
    return YES;
}

- (NSString*) identifier
{
    return [NSString stringWithFormat:@"SBC_LAM %d",[self slot]];
}

- (ORReadOutList*) readoutGroup
{
    return readoutGroup;
}

- (void) setReadoutGroup:(ORReadOutList*)newreadoutGroup
{
    [readoutGroup autorelease];
    readoutGroup=[newreadoutGroup retain];
}

- (NSMutableArray*) children 
{
    //methods exists to give common interface across all objects for display in lists
    return [NSMutableArray arrayWithObjects:readoutGroup,nil];
}


- (NSMutableArray *) variableNames
{
    return variableNames; 
}

- (void) setVariableNames: (NSMutableArray *) VariableNames
{
    [VariableNames retain];
    [variableNames release];
    variableNames = VariableNames;
}
- (BOOL) isBusy
{
	return busy;
}

- (void) processPacket:(SBC_Packet*)aPacket
{
	busy = YES;
	memcpy(&sbcPacket, aPacket, sizeof(SBC_Packet));
}

- (id)initWithCoder:(NSCoder*)decoder
{
    self = [super initWithCoder:decoder];
    
    [[self undoManager] disableUndoRegistration];
    [self setReadoutGroup:[decoder decodeObjectForKey:@"LAMGroup1"]];
    [self setVariableNames:[decoder decodeObjectForKey: @"LAMVariables"]];
    if(!variableNames)[self setVariableNames:[NSMutableArray array]];
    
    [self setSlot:[decoder decodeIntForKey:@"LAMSlot"]];
    [[self undoManager] enableUndoRegistration];
    return self;
}

- (void)encodeWithCoder:(NSCoder*)encoder
{
    [super encodeWithCoder:encoder];
    [encoder encodeObject:[self readoutGroup] forKey:@"LAMGroup1"];
    [encoder encodeObject: variableNames forKey: @"LAMVariables"];
    [encoder encodeInt:[self slot] forKey:@"LAMSlot"];
}

#pragma mark ***Data Taker
- (void) runTaskStarted:(ORDataPacket*)aDataPacket userInfo:(NSDictionary*)userInfo
{
	dataTakers = [[readoutGroup allObjects] retain];	//cache of data takers.
	NSEnumerator* e = [dataTakers objectEnumerator];
	id obj;
	while(obj = [e nextObject]){
		[obj runTaskStarted:aDataPacket userInfo:userInfo];
	}
	cachedNumberOfDataTakers = [dataTakers count];
}

- (void) saveReadOutList:(NSFileHandle*)aFile
{
    [readoutGroup saveUsingFile:aFile];
}

- (void) loadReadOutList:(NSFileHandle*)aFile
{
    [self setReadoutGroup:[[[ORReadOutList alloc] initWithIdentifier:@"Trigger 1"]autorelease]];
    [readoutGroup loadUsingFile:aFile];
}

//**************************************************************************************
// Function:	TakeData
// Description: Read data from a card
//**************************************************************************************
-(void) takeData:(ORDataPacket*)aDataPacket userInfo:(id)params
{
    NSString* errorLocation = @"";
    @try {
		if(busy){  
            
            //check if any data for the data stream
			errorLocation = @"LAM Data Shipped";
			//[aDataPacket addLongsToFrameBuffer:&eCpuLAMStruct.formatedDataWord[0] length:eCpuLAMStruct.numberDataWords];
            
            //check if any userData for the Children
            int i;
			//if(!params)params = [NSMutableDictionary dictionary];
			// for(i=0;i<eCpuLAMStruct.numberUserInfoWords;i++){
            //    if(i< [variableNames count] && [variableNames objectAtIndex:i]!=nil){
            //        [params setObject:[NSNumber numberWithLong:eCpuLAMStruct.userInfoWord[i]] forKey:[variableNames objectAtIndex:i]];
            //    }
            //}
            
			// macLAMStruct.lamAcknowledged_counter = eCpuLAMStruct.lamFired_counter;
			
			errorLocation = @"Clearing LAM";
            busy = NO;
		 	
			errorLocation = @"LAM Reading Children";
            for(i=0;i<cachedNumberOfDataTakers;i++){
                [[dataTakers objectAtIndex:i] takeData:aDataPacket userInfo:params];
            }
            
        }
        
	}
	@catch(NSException* localException) {
		NSLogError(@"",@"LAM Exception Error",errorLocation,nil);
		[localException raise];
	}
}


- (void) runTaskStopped:(ORDataPacket*)aDataPacket userInfo:(NSDictionary*)userInfo
{
	NSEnumerator* e = [dataTakers objectEnumerator];
	id obj;
	while(obj = [e nextObject]){
		[obj runTaskStopped:aDataPacket userInfo:userInfo];
	}
	[dataTakers release];
	dataTakers = nil;
	cachedNumberOfDataTakers = 0;
}

- (void) reset {}

- (int) load_HW_Config_Structure:(SBC_crate_config*)configStruct index:(int)index
{
	//even tho this object can have 'children', the SBC doesn't read them out
	//still, this stucture needs to be defined to tell the SBC to monitor and report LAMs
	configStruct->total_cards++;
	configStruct->card_info[index].hw_type_id = kSBCLAM;	 //should be unique
	configStruct->card_info[index].hw_mask[0] = -1;			 //doesn't produce any records
	configStruct->card_info[index].slot 	  = [self slot];
	configStruct->card_info[index].crate 	  = -1;
	configStruct->card_info[index].add_mod 	  = -1;
	configStruct->card_info[index].base_add   = -1;	
	configStruct->card_info[index].num_Trigger_Indexes 	= 0; 
	configStruct->card_info[index].next_Card_Index 	= index+1;	
	return index+1;
}

@end

