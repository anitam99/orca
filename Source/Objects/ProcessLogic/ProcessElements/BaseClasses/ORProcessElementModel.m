//
//  ORProcessElementModel.m
//  Orca
//
//  Created by Mark Howe on 11/19/05.
//  Copyright 2005 CENPA, University of Washington. All rights reserved.
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


#import "ORProcessElementModel.h"
#import "NSNotifications+Extensions.h"

NSString* ORProcessElementStateChangedNotification  = @"ORProcessElementStateChangedNotification";
NSString* ORProcessCommentChangedNotification       = @"ORProcessCommentChangedNotification";

@implementation ORProcessElementModel

#pragma mark ���Inialization
- (id) init //designated initializer
{
    self = [super init];
    processLock = [[NSLock alloc] init];
    [self setUpNubs];
    return self;
}

- (void) dealloc
{
	[highlightedAltImage release];
    [altImage release];
	[processLock release];
    [super dealloc];
}

- (void) awakeAfterDocumentLoaded
{
    [self setUpNubs];
}

- (NSString*) helpURL
{
	return @"Process_Control/Process_Elements.html";
}

- (void) setUpNubs
{
}

- (NSString*) shortName
{
	return @"";
}

- (BOOL) useAltView
{
	return useAltView;
}

- (void) setUseAltView:(BOOL)aState
{
	useAltView = aState;
	[self setUpImage];
}

- (int) compareStringTo:(id)anElement usingKey:(NSString*)aKey
{
    NSString* ourKey   = [self valueForKey:aKey];
    NSString* theirKey = [anElement valueForKey:aKey];
    if(!ourKey && theirKey)         return 1;
    else if(ourKey && !theirKey)    return -1;
    else if(!ourKey || !theirKey)   return 0;
    return [ourKey compare:theirKey];
}

#pragma mark ���AltImage Methods
- (NSImage*) altImage
{
	//sub-classes define an image if they are to appear on the Normal View
	return nil;
}
- (BOOL) canBeInAltView
{
	return NO;
}
- (void) setImage:(NSImage*)anImage
{
	if(![self useAltView])[super setImage:anImage];
	else {
		[anImage retain];
		[altImage release];
		altImage = anImage;
		
		if(anImage){
			NSSize aSize = [anImage size];
			altFrame.size.width = aSize.width;
			altFrame.size.height = aSize.height;
			altBounds.size.width = aSize.width;
			altBounds.size.height = aSize.height;
			NSRect sourceRect = NSMakeRect(0,0,[anImage size].width,[anImage size].height);
			[highlightedAltImage release];
			highlightedAltImage = [[NSImage alloc] initWithSize:[anImage size]];
			[highlightedAltImage lockFocus];
			[anImage dissolveToPoint:NSZeroPoint fraction:1];
			[[NSColor colorWithCalibratedWhite:0.0 alpha:0.5] set];
			NSRectFillUsingOperation(sourceRect, NSCompositeSourceAtop);
			[NSBezierPath strokeRect:sourceRect];
			[highlightedAltImage unlockFocus];
		}
		else {
			altFrame.size.width 	= 0;
			altFrame.size.height 	= 0;
			altBounds.size.width 	= 0;
			altBounds.size.height 	= 0;
			[highlightedAltImage release];
			highlightedAltImage = nil;
		}  
	}
}

- (void) drawConnections:(NSRect)aRect withTransparency:(float)aTransparency
{
	if(![self useAltView])[super drawConnections:aRect withTransparency:aTransparency];
}

- (NSString*) iconLabel { return nil; }
- (NSString*) iconValue { return nil; }

- (void) drawIcon:(NSRect)aRect withTransparency:(float)aTransparency
{
	if(![self useAltView]){
		[super drawIcon:aRect withTransparency:aTransparency];
	}
	else {
		if(![self altImage])return;
		//a workaround for a case where image hasn't been made yet.. don't worry--it will get made below if need be.
		if(aRect.size.height == 0)aRect.size.height = 1;
		if(aRect.size.width == 0)aRect.size.width = 1;
		NSShadow* theShadow = nil;
		
		if(NSIntersectsRect(aRect,altFrame)){
			
			if([self guardian]){
				[NSGraphicsContext saveGraphicsState]; 
				
				// Create the shadow below and to the right of the shape.
				theShadow = [[NSShadow alloc] init]; 
				[theShadow setShadowOffset:NSMakeSize(3.0, -3.0)]; 
				[theShadow setShadowBlurRadius:3.0]; 
				
				// Use a partially transparent color for shapes that overlap.
				[theShadow setShadowColor:[[NSColor blackColor]
										   colorWithAlphaComponent:0.3]]; 
				
				[theShadow set];
			}
			// Draw.
			if(!altImage){
				[self setUpImage];
			}
			if(altImage){
				NSImage* imageToDraw;
				if([self highlighted])	imageToDraw = highlightedAltImage;
				else					imageToDraw = altImage;
				
				NSRect sourceRect = NSMakeRect(0,0,[imageToDraw size].width,[imageToDraw size].height);
				[imageToDraw drawAtPoint:altFrame.origin fromRect:sourceRect operation:NSCompositeSourceOver fraction:aTransparency];
			}
			else {
				//no icon so fake it with just a square
				if([self highlighted])	[[NSColor redColor]set];
				else					[[NSColor blueColor]set];
				NSFrameRect(frame);
				NSAttributedString* s = [[NSAttributedString alloc] initWithString:@"No Icon"];
				[s drawAtPoint:altFrame.origin];
				[s release];
			}
			
			if([self guardian]){
				[NSGraphicsContext restoreGraphicsState];
			}        
		}
		[theShadow release]; 
	}
}

- (void) drawImageAtOffset:(NSPoint)anOffset withTransparency:(float)aTransparency
{
	if(![self useAltView]){
		[super drawImageAtOffset:anOffset withTransparency:aTransparency];
	}
	else {
		BOOL saveState = [self highlighted];
		NSRect oldFrame = altFrame;
		NSRect aFrame = altFrame;
		aFrame.origin.x += anOffset.x;
		aFrame.origin.y += anOffset.y;
		altFrame = aFrame;
		[self setHighlighted:NO];
		[self setSkipConnectionDraw:YES];
		[self drawSelf:altFrame withTransparency:aTransparency];
		[self setSkipConnectionDraw:NO];
		[self setOffset:NSMakePoint(altFrame.origin.x,altFrame.origin.y)];
		altFrame = oldFrame;
		
		[self setHighlighted:saveState];
	}
}

- (NSImage*)image
{
	if(![self useAltView])	return [super image];
    else					return [self altImage];
}

- (int)	x
{
	if(![self useAltView])	return [super x];
	else					return altFrame.origin.x;
}

- (int) y
{
 	if(![self useAltView])	return [super y];
	else					return  altFrame.origin.y;
}

- (void) setFrame:(NSRect)aValue
{
	if(![self useAltView]){
		[super  setFrame:aValue];
	}
	else {
		altFrame = aValue;
		altBounds.size = altFrame.size;
	}
}

- (BOOL) acceptsClickAtPoint:(NSPoint)aPoint
{
	if(![self canBeInAltView]) return NO;
	else return [super acceptsClickAtPoint:aPoint];
}
- (BOOL) intersectsRect:(NSRect) aRect
{
	if(![self canBeInAltView]) return NO;
	else return [super intersectsRect:aRect];
}

- (ORConnector*) requestsConnection: (NSPoint)aPoint
{
	if(![self useAltView] || ![self canBeInAltView])	return [super requestsConnection:aPoint];
	else return nil;
}

- (NSRect) frame
{
	if(![self useAltView] || ![self canBeInAltView])	return [super frame];
	else					return altFrame;
}

- (void) setBounds:(NSRect)aValue
{
	if(![self useAltView] || ![self canBeInAltView])	[super setBounds:aValue];
	else					altBounds = aValue;
}

- (NSRect) bounds
{
	if(![self useAltView] || ![self canBeInAltView])	return [super bounds];
    else					return altBounds;
}

- (void) setOffset:(NSPoint)aPoint
{
	if(![self useAltView] || ![self canBeInAltView])	[super setOffset:aPoint];
	else					altOffset = aPoint;
}

- (NSPoint)offset
{
    if(![self useAltView] || ![self canBeInAltView])	return [super offset];
	else					return altOffset;
}

- (void) setGuardian:(id)aGuardian
{
	[super setGuardian:aGuardian];
	if([aGuardian useAltView]){
		altFrame.origin = frame.origin;
	}
}

- (void) moveTo:(NSPoint)aPoint
{	
	if(![self useAltView]){
		[super moveTo:aPoint];
	}
	else {
		[[[self undoManager] prepareWithInvocationTarget:self] moveTo:altFrame.origin];
		altFrame.origin = aPoint;
		
		NSMutableDictionary* userInfo = [NSMutableDictionary dictionary];
		[userInfo setObject:self forKey: ORMovedObject];
		
		[[NSNotificationCenter defaultCenter] postNotificationName:OROrcaObjectMoved object:self userInfo: userInfo];
	}
}

-(void) move:(NSPoint)aPoint
{
	if(![self useAltView])[super move:aPoint];
    else [self moveTo:NSMakePoint(altFrame.origin.x+aPoint.x,altFrame.origin.y+aPoint.y)];
}

#pragma mark ���Accessors
- (NSString*) elementName{ return @"Processor"; }
- (NSString*) fullHwName { return @"N/A"; }
- (id) stateValue		 { return @"-"; }

- (NSString*) description:(NSString*)prefix
{
    return [NSString stringWithFormat:@"%@%@ %d",prefix,[self elementName],[self uniqueIdNumber]];
}

- (NSString*)comment
{
    return comment;
}
- (void) setComment:(NSString*)aComment
{
    if(!aComment)aComment = @"";
    [[[self undoManager] prepareWithInvocationTarget:self] setComment:comment];
    
    [comment autorelease];
    comment = [aComment copy];
    
    [[NSNotificationCenter defaultCenter]
		postNotificationName:ORProcessCommentChangedNotification
                              object:self];
}

- (void) setUniqueIdNumber :(unsigned long)aNumber
{
    [super setUniqueIdNumber:aNumber];
    [self postStateChange]; //force redraw
}


- (void) setState:(int)value
{
	@try {
		[processLock lock];     //start critical section
		if(value != state){
			state = value;
			[self postStateChange];
		}
	}
	@finally {
		[processLock unlock];   //end critical section
	}
}

- (int) state
{
    return state;
}

- (void) setEvaluatedState:(int)value
{
	@try {
		[processLock lock];     //start critical section
		if(value != evaluatedState){
			evaluatedState = value;
			[self postStateChange];
		}
	}
	@finally {
		[processLock unlock];   //end critical section
	}
}

- (int)   evaluatedState  { return evaluatedState; }
- (Class) guardianClass   { return NSClassFromString(@"ORProcessModel"); }
- (BOOL)  acceptsGuardian: (OrcaObject*)aGuardian { return [aGuardian isKindOfClass:[self guardianClass]]; }
- (BOOL)  canImageChangeWithState { return NO; }

#pragma mark ���Thread Related
- (void) clearAlreadyEvaluatedFlag	{ alreadyEvaluated = NO; }
- (BOOL) alreadyEvaluated			{ return alreadyEvaluated; }
- (void) processIsStarting			{ partOfRun = YES; }
- (void) processIsStopping			{ partOfRun = NO; }
- (BOOL) partOfRun					{ return partOfRun; }
- (int) eval						{ return 0; }

- (void) postStateChange
{
	if([self canImageChangeWithState])[self performSelectorOnMainThread:@selector(setUpImage) withObject:nil waitUntilDone:NO];
	[[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:ORProcessElementStateChangedNotification object:self userInfo:nil waitUntilDone:NO]; 
}

- (void) drawSelf:(NSRect)aRect withTransparency:(float)aTransparency
{
	[super drawSelf:aRect withTransparency:aTransparency];
}

#pragma mark ���Archiving
- (id) initWithCoder:(NSCoder*)decoder
{
    self = [super initWithCoder:decoder];
    
    [[self undoManager] disableUndoRegistration];
    [self setComment:[decoder decodeObjectForKey:@"comment"]];
	useAltView =	 [decoder decodeBoolForKey:@"useAltView"];
	altFrame  =		 [decoder decodeRectForKey:@"altFrame"];
	altOffset =		 [decoder decodePointForKey:@"altOffset"];
	altBounds =		 [decoder decodeRectForKey:@"altBounds"];

    [[self undoManager] enableUndoRegistration];
	
    processLock = [[NSLock alloc] init];
    [self setUpNubs];
	
    return self;
}

- (void) encodeWithCoder:(NSCoder*)encoder
{
    [super encodeWithCoder:encoder];
    [encoder encodeBool:useAltView  forKey:@"useAltView"];
    [encoder encodeObject:comment  forKey:@"comment"];
    [encoder encodeRect:altFrame   forKey:@"altFrame"];
    [encoder encodePoint:altOffset forKey:@"altOffset"];
	[encoder encodeRect:altBounds  forKey:@"altBounds"];
}

@end
