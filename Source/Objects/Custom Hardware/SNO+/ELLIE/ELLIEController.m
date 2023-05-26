//
//  ELLIEController.m
//  Orca
//
//  Created by Chris Jones on 01/04/2014.
//
//  Revision history:
//  Ed Leming 04/01/2016 -  Removed global variables to move logic to
//                          ELLIEModel
//
//  Anita Masuskapoe Nov 30, 2022 - Adding push to DB button to save node/fiber
//                          variables to CouchDB.  Autofill now loads from tellieconfig
//                          databases: fibre_main, general, pca
//


#import "ELLIEController.h"
#import "ELLIEModel.h"
#import "SNOPModel.h"
#import "TUBiiModel.h"
#import "SNOP_Run_Constants.h"
#import "ORRunModel.h"
#import "ORCouchDB.h"

@implementation ELLIEController

@synthesize nodeMapWC = _nodeMapWC;
@synthesize guiFireSettings = _guiFireSettings;
@synthesize tellieThread = _tellieThread;
@synthesize smellieThread = _smellieThread;
@synthesize delegates = _delegates;

//Set up functions
-(id)init
{
    self = [super initWithWindowNibName:@"ellie"];
    @try{
        [self fetchConfigurationFile:nil];
        [self initialiseTellie];
    } @catch (NSException *e) {
        NSLog(@"CouchDB for ELLIE isn't connected properly. Please reload the ELLIE Gui and check the database connections\n");
        NSLog(@"Reason for error %@ \n",e);
    }
    [tellieServerResponseTf setEditable:NO];
    [smellieServerResponseTf setEditable:NO];
    [interlockServerResponseTf setEditable:NO];
    return self;
}

-(void) awakeFromNib
{
    [super awakeFromNib];
    [self updateWindow];
    [self updateServerSettings:nil];
    [self fetchConfigurationFile:nil];
    [self initialiseTellie];
    [tellieServerResponseTf setEditable:NO];
    [smellieServerResponseTf setEditable:NO];
    [interlockServerResponseTf setEditable:NO];
}

- (void)dealloc
{
    [_nodeMapWC release];
    [_smellieThread release];
    [_guiFireSettings release];
    [_tellieThread release];
    [_delegates release];
    [super dealloc];
}

- (void) updateWindow
{
    [super updateWindow];
}

- (void) updateServerSettings:(NSNotification *)aNote
{
    [tellieHostTf setStringValue:[model tellieHost]];
    [telliePortTf setStringValue:[model telliePort]];

    [smellieHostTf setStringValue:[model smellieHost]];
    [smelliePortTf setStringValue:[model smelliePort]];

    [interlockHostTf setStringValue:[model interlockHost]];
    [interlockPortTf setStringValue:[model interlockPort]];
}

- (void) updateTuningRunCB:(NSNotification *)aNote
{
    [tellieExpertTuningCb setState:[[model tuningRun]boolValue]];
}

- (IBAction) serverSettingsChanged:(id)sender {
    /* Settings tab changed. Set the model variables in ELLIEModel. */
    [model setTelliePort:[telliePortTf stringValue]];
    [model setTellieHost:[tellieHostTf stringValue]];

    [model setSmelliePort:[smelliePortTf stringValue]];
    [model setSmellieHost:[smellieHostTf stringValue]];

    [model setInterlockPort:[interlockPortTf stringValue]];
    [model setInterlockHost:[interlockHostTf stringValue]];
}

#pragma mark •••Notifications
- (void) registerNotificationObservers
{
    NSNotificationCenter* notifyCenter = [NSNotificationCenter defaultCenter];

    [super registerNotificationObservers];

    [notifyCenter removeObserver:self name:NSWindowDidResignKeyNotification object:nil];

    [notifyCenter addObserver : self
                     selector : @selector(tellieRunFinished:)
                         name : ORTELLIERunFinishedNotification
                        object: nil];

    [notifyCenter addObserver : self
                     selector : @selector(displayAmellieNodes:)
                         name : ORAMELLIEMappingReceived
                        object: nil];

    [notifyCenter addObserver : self
                     selector : @selector(updateServerSettings:)
                         name : @"ELLIEServerSettingsChanged"
                        object: nil];

    [notifyCenter addObserver : self
                     selector : @selector(updateTuningRunCB:)
                         name : @"ELLIETuningButtonChanged"
                        object: nil];

    [notifyCenter addObserver : self
                     selector : @selector(killInterlock:)
                         name : @"SMELLIEEmergencyStop"
                        object: nil];

    [notifyCenter addObserver : self
                     selector : @selector(tubiiDied:)
                         name : @"TUBiiKeepAliveDied"
                       object : nil];
}

-(void)fetchConfigurationFile:(NSNotification *)aNote{
    /*
     When the run files are loaded we re-load the smellie config file, just incase
    */
    [model fetchCurrentSmellieConfig];
}

///////////////////////////////////////////
// TELLIE Functions
///////////////////////////////////////////
-(void)initialiseTellie
{
    // Load static (calibration and mapping) parameters from DB.
    [model loadTELLIEStaticsFromDB];
    [model loadAMELLIEStaticsFromDB];
    
    //Make sure sensible tabs are selected to begin with
    [ellieTabView selectTabViewItem:tellieTViewItem];
    [tellieTabView selectTabViewItem:tellieFireFibreTViewItem];
    [tellieOperatorTabView selectTabViewItem:tellieGeneralOpTViewItem];
    
    //Set slave mode operation as default for both tabs
    [tellieGeneralOperationModePb removeAllItems];
    [tellieGeneralOperationModePb addItemsWithTitles:@[@"Slave", @"Master"]];
    [tellieGeneralOperationModePb selectItemAtIndex:0];

    [tellieExpertOperationModePb removeAllItems];
    [tellieExpertOperationModePb addItemsWithTitles:@[@"Slave", @"Master"]];
    [tellieExpertOperationModePb selectItemAtIndex:0];
    [tellieExpertOperationModePb setEnabled:NO];
    
    [amellieOperationModePb removeAllItems];
    [amellieOperationModePb addItemsWithTitles:@[@"Slave", @"Master"]];
    [amellieOperationModePb selectItemAtIndex:0];

    [amellieNodeSelectPb removeAllItems];
    [amellieAngleSelectPb removeAllItems];

    //Grey out fibre until node is given
    [tellieGeneralFibreSelectPb setTarget:self];
    [tellieGeneralFibreSelectPb setEnabled:NO];
    
    [tellieExpertFibreSelectPb setTarget:self];
    [tellieExpertFibreSelectPb setEnabled:NO];
    
    //Disable Fire / stop buttons
    [tellieExpertFireButton setEnabled:NO];
    [tellieExpertStopButton setEnabled:NO];
    [tellieConfigPushToDB setEnabled:NO];
    [tellieGeneralFireButton setEnabled:NO];
    [tellieGeneralStopButton setEnabled:NO];
    [amellieFireButton setEnabled:NO];
    [amellieStopButton setEnabled:NO];
    
    //Set this object as delegate for textFields
    //This means we get notified when someone's edited
    //a field.
    [tellieGeneralNodeTf setDelegate:self];
    [tellieGeneralPhotonsTf setDelegate:self];
    [tellieGeneralTriggerDelayTf setDelegate:self];
    [tellieGeneralNoPulsesTf setDelegate:self];
    [tellieGeneralFreqTf setDelegate:self];
    [tellieGeneralTriggerDelayTf setStringValue:@"800"];

    [tellieChannelTf setDelegate:self];
    [telliePulseWidthTf setDelegate:self];
    [telliePulseFreqTf setDelegate:self];
    [tellieFibreDelayTf setDelegate:self];
    [tellieTriggerDelayTf setDelegate:self];
    [tellieNoPulsesTf setDelegate:self];
    [tellieExpertNodeTf setDelegate:self];
    [telliePinTimeoutTf setDelegate:self];
    
    [amelliePulseWidthTf setDelegate:self];
    [amelliePulseFreqTf setDelegate:self];
    [amelliePulseHeightTf setDelegate:self];
    [amellieFibreDelayTf setDelegate:self];
    [amellieTriggerDelayTf setDelegate:self];
    [amellieNoPulsesTf setDelegate:self];
    [amellieNodeSelectPb setTarget:self];
    [amellieAngleSelectPb setTarget:self];
    [amellieNodeSelectPb setAction:@selector(updateAmellieAngles:)];
    [amellieAngleSelectPb setAction:@selector(updateAmellieChannel)];
    [amellieTriggerDelayTf setStringValue:@"650"];
    [amelliePulseHeightTf setStringValue:@"16383"];

    // Build custom run tab
    [tellieBuildPushToDB setEnabled:NO];
    [tellieBuildOpMode removeAllItems];
    [tellieBuildOpMode addItemsWithTitles:@[@"Slave", @"Master"]];
    [tellieBuildTrigDelay setStringValue:@"650"];
    for(int i=0; i<100; i++){
        if(i<92){
            [[tellieBuildNodeSelection cellWithTag:i] setEnabled:YES];
            [[tellieBuildNodeSelection cellWithTag:i] setState:1];
        } else {
            [[tellieBuildNodeSelection cellWithTag:i] setEnabled:NO];
            [[tellieBuildNodeSelection cellWithTag:i] setState:0];
        }
    }

}

-(NSString*)extractNumberFromText:(NSString *)text
{
    NSCharacterSet *nonDigitCharacterSet = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    return [[text componentsSeparatedByCharactersInSet:nonDigitCharacterSet] componentsJoinedByString:@""];
}

-(void)displayAmellieNodes:(id)sender
{
    // Fill the NSPopUpButton
    [amellieNodeSelectPb setEnabled:YES];

    // Find panel (node) numbers
    NSMutableArray* panels = [[NSMutableArray alloc] init];
    for(id key in [model amellieNodeMapping]){
        if ([key rangeOfString:@"panel"].location == NSNotFound) {
            continue;
        } else {
            NSUInteger num = [[self extractNumberFromText:key] integerValue];
            [panels addObject:[NSString stringWithFormat:@"%d",(int)num]];
        }
    }
    // Once we get a note saying mapping is loaded, fill the push button
    for(id panel in panels){
        @try{
            [amellieNodeSelectPb addItemWithTitle:panel];
        } @catch(NSException * e){
            NSLog(@"[AMELLIE]: Problem setting panel select option : %@\n", [e reason]);
        }
    }
    [panels release];
    // Select the first one and make sure the channel field gets set appropriately
    //[amellieNodeSelectPb selectItemAtIndex:0];
}

-(void)updateAmellieAngles:(NSMenuItem *)sender
{
    [amellieAngleSelectPb removeAllItems];
    [amellieAngleSelectPb setEnabled:YES];

    NSString* panel_name = [NSString stringWithFormat:@"panel_%@", [amellieNodeSelectPb titleOfSelectedItem]];
    NSDictionary* angle_to_fibre = [[model amellieNodeMapping] objectForKey:panel_name];
    for(id angle in angle_to_fibre){
        @try{
            [amellieAngleSelectPb addItemWithTitle:angle];
        } @catch(NSException * e){
            NSLog(@"[AMELLIE]: Problem setting angle select option : %@\n", [e reason]);
        }
    }
    // When someone changes the Fibre selection, automatically update the channel field
    [amellieAngleSelectPb selectItemAtIndex:0];
    [self updateAmellieChannel];
}

-(void)updateAmellieChannel
{
    NSString* panel_name = [NSString stringWithFormat:@"panel_%@", [amellieNodeSelectPb titleOfSelectedItem]];
    NSDictionary* angle_to_fibre = [[model amellieNodeMapping] objectForKey:panel_name];
    NSString* fibre = [angle_to_fibre objectForKey:[amellieAngleSelectPb titleOfSelectedItem]];
    // When someone changes the Fibre selection, automatically update the channel field
    [amellieChannelTf setStringValue:[NSString stringWithFormat:@"%@",[model calcAmellieChannelForFibre:fibre]]];
}

-(IBAction)tellieGeneralFireAction:(id)sender
{
    ////////////
    // Check a run isn't ongoing
    if([model ellieFireFlag]){
        NSLogColor([NSColor redColor], @"[TELLIE]: Fire button will not work while an ELLIE run is underway\n");
        return;
    }
    
    [tellieGeneralFireButton setEnabled:NO];
    [tellieGeneralStopButton setEnabled:YES];
    [[NSNotificationCenter defaultCenter] postNotificationName:ORTELLIEGeneralRunStartNotification object:nil userInfo:[self guiFireSettings]];
    [tellieGeneralValidationStatusTf setStringValue:@""];
}

-(IBAction)tellieExpertFireAction:(id)sender
{
    ////////////
    // Check a run isn't ongoing
    if([model ellieFireFlag]){
        NSLogColor([NSColor redColor], @"[TELLIE]: Fire button will not work while an ELLIE run is underway\n");
        return;
    }
    
    [tellieExpertStopButton setEnabled:YES];
    [[NSNotificationCenter defaultCenter] postNotificationName:ORTELLIERunStartNotification object:nil userInfo:[self guiFireSettings]];
    [tellieExpertFireButton setEnabled:NO];
    [tellieExpertValidationStatusTf setStringValue:@""];
}

-(IBAction)tellieGeneralStopAction:(id)sender
{
    [model stopTellieRun];
}

-(IBAction)tellieExpertStopAction:(id)sender
{
    [model stopTellieRun];
}

-(void)tellieRunFinished:(NSNotification *)aNote
{
    [tellieGeneralStopButton setEnabled:NO];
    [tellieExpertStopButton setEnabled:NO];
}

- (BOOL) isNumeric:(NSString *)s{
    NSScanner *sc = [NSScanner scannerWithString: s];
    if( [sc scanFloat:NULL] )
    {
        return [sc isAtEnd];
    }
    return NO;
}

-(IBAction)tellieNodeMapAction:(id)sender
{
    // Does map window already exist? If so release it and create a new one.
    // I can't find a more elegant way to force the window back to the
    // front of the screen.... Annoying.
    NSWindowController* tmpWc = [[NSWindowController alloc] initWithWindowNibName:@"NodeMap"];
    
    if([self nodeMapWC] != nil){
        [self setNodeMapWC:nil];
        [self setNodeMapWC:tmpWc];
        [[self nodeMapWC] showWindow:self];
        [tmpWc release];
        return;
    }
    
    // Set member window controller
    [self setNodeMapWC:tmpWc];
    [[self nodeMapWC] showWindow:self];
    [tmpWc release];
}

- (IBAction)tellieGeneralFibreNameAction:(NSPopUpButton *)sender {
    //[tellieGeneralPhotonsTf setStringValue:@""];
    //[tellieGeneralNoPulsesTf setStringValue:@""];
    //[tellieGeneralTriggerDelayTf setStringValue:@""];
    //[tellieGeneralFreqTf setStringValue:@""];
    [tellieGeneralFireButton setEnabled:NO];
    [tellieGeneralStopButton setEnabled:NO];
}

- (IBAction)tellieExpertFibreNameAction:(NSPopUpButton *)sender {
    [tellieChannelTf setStringValue:@""];
    [telliePulseWidthTf setStringValue:@""];
    [telliePulseFreqTf setStringValue:@""];
    [tellieFibreDelayTf setStringValue:@""];
    [tellieTriggerDelayTf setStringValue:@""];
    [tellieNoPulsesTf setStringValue:@""];
    [telliePinTimeoutTf setStringValue:@""];
    [tellieExpertValidationStatusTf setStringValue:@""];
    [tellieExpertFireButton setEnabled:NO];
    [tellieConfigPushToDB setEnabled:NO];
    [tellieExpertValidateSettingsButton setEnabled:NO];
    [tellieExpertOperationModePb selectItemAtIndex:0];
    [tellieExpertOperationModePb setEnabled:NO];
}

-(IBAction)tellieGeneralModeAction:(NSPopUpButton *)sender{
    [tellieGeneralFireButton setEnabled:NO];
}

-(IBAction)tellieExpertModeAction:(NSPopUpButton *)sender{
    [tellieExpertFireButton setEnabled:NO];
    [tellieConfigPushToDB setEnabled:NO];
    [self tellieExpertInitPCASettings];
}

- (IBAction)tellieExpertTuningAction:(id)sender {
    [model setTuningRun:[NSNumber numberWithInteger:[tellieExpertTuningCb state]]];
}

// New - November 30, 2022 - Anita Masuskapoe
//
- (void)tellieExpertInitPCASettings{
    NSMutableDictionary* pcasettings = [[model returnTelliePCASettings] valueForKey:[tellieExpertOperationModePb titleOfSelectedItem]];
    
    // Configure PCA settings
    if (pcasettings){
        [tellieExpertOperationModePb setEnabled:YES];
        [tellieTriggerDelayTf setStringValue:[pcasettings objectForKey:@"trigger_delay"]];
        [telliePulseFreqTf setStringValue:[pcasettings objectForKey:@"trigger_rate"]];
        [tellieNoPulsesTf setStringValue:[pcasettings objectForKey:@"n_pulses"]];
    }else{
        [tellieExpertValidationStatusTf setStringValue:@"Issue obtaining PCA settings. See orca log for full details."];
        [tellieTriggerDelayTf setStringValue:@""];
        [telliePulseFreqTf setStringValue:@""];
        [tellieNoPulsesTf setStringValue:@""];
    }
}

// Extensive changes - November 30, 2022 - Anita Masuskapoe
//
//      Routine now retrieves last used fibre settings
//      from database
//
- (IBAction)tellieExpertAutoFillAction:(id)sender {
    
    // Deselect the node text field
    [tellieExpertNodeTf resignFirstResponder];
    
    // Clear all current values
    [tellieChannelTf setStringValue:@""];
    [telliePulseWidthTf setStringValue:@""];
    [telliePulseFreqTf setStringValue:@""];
    [tellieFibreDelayTf setStringValue:@""];
    [tellieTriggerDelayTf setStringValue:@""];
    [tellieNoPulsesTf setStringValue:@""];
    [telliePinTimeoutTf setStringValue:@""];
    [tellieExpertValidateSettingsButton setEnabled:YES];
    [tellieConfigPushToDB setEnabled:NO];
    [tellieExpertFireButton setEnabled:NO];
    [tellieExpertOperationModePb setEnabled:NO];
        
    // Get configured fibre
    NSString *ActiveFibre = [tellieExpertFibreSelectPb titleOfSelectedItem];
    // Delete active fibre a/b from fibre name
    NSString *fibre = @"";
    if ([ActiveFibre length] > 0) {
        fibre = [ActiveFibre substringToIndex:[ActiveFibre length] - 1];
    }
    
    // Configure formatter
    NSNumberFormatter *f = [[NSNumberFormatter alloc] init];
    f.numberStyle = NSNumberFormatterDecimalStyle;
            
    // Get and set Channel from expert channel-fibre mapping
    NSNumber *channel = [model calcTellieExpertChannelForFibre:fibre];
    [tellieChannelTf setStringValue:[channel stringValue]];
    if (![channel isEqual:@-2]){
        // Defaults to slave mode
        [tellieExpertOperationModePb selectItemAtIndex:0];
        // Retrieve settings for slave mode
        [self tellieExpertInitPCASettings];
                
        //--- Configure fibre main settings ----------
        NSMutableDictionary* mainsettings = [model returnTellieFibreMainSettings:fibre];
        
        // Configure fibre main settings-
        if (mainsettings){
            [tellieFibreDelayTf setStringValue:[NSString stringWithFormat:@"%@",[mainsettings objectForKey:@"fibre_delay"]]];
            [telliePulseWidthTf setStringValue:[NSString stringWithFormat:@"%@",[mainsettings objectForKey:@"pulse_width"]]];
        }else{
            [tellieExpertValidationStatusTf setStringValue:@"Issue generating settings. See orca log for full details."];
            [tellieFibreDelayTf setStringValue:@""];
            [telliePulseWidthTf setStringValue:@""];
        }
        
        //--- Configure general settings ----------
        NSMutableDictionary* gensettings = [model returnTellieGeneralSettings];
        // Configure general settings
        if (gensettings){
            [telliePinTimeoutTf setStringValue:[NSString stringWithFormat:@"%@",[gensettings objectForKey:@"subrun_delay"]]];
        }else{
            [tellieExpertValidationStatusTf setStringValue:@"Issue generating settings. See orca log for full details."];
            [telliePinTimeoutTf setStringValue:@""];
        }
        
        //Set backgrounds back to white
        [tellieChannelTf setBackgroundColor:[NSColor whiteColor]];
        [telliePulseWidthTf setBackgroundColor:[NSColor whiteColor]];
        [tellieFibreDelayTf setBackgroundColor:[NSColor whiteColor]];
        [telliePulseFreqTf setBackgroundColor:[NSColor whiteColor]];
        [tellieNoPulsesTf setBackgroundColor:[NSColor whiteColor]];
        [tellieTriggerDelayTf setBackgroundColor:[NSColor whiteColor]];
        [telliePinTimeoutTf setBackgroundColor:[NSColor whiteColor]];
    }else{
        [tellieExpertOperationModePb selectItemAtIndex:0];
        [tellieChannelTf setBackgroundColor:[NSColor orangeColor]];
        [telliePulseWidthTf setBackgroundColor:[NSColor whiteColor]];
        [tellieFibreDelayTf setBackgroundColor:[NSColor whiteColor]];
        [telliePulseFreqTf setBackgroundColor:[NSColor whiteColor]];
        [tellieNoPulsesTf setBackgroundColor:[NSColor whiteColor]];
        [tellieTriggerDelayTf setBackgroundColor:[NSColor whiteColor]];
        [telliePinTimeoutTf setBackgroundColor:[NSColor whiteColor]];
    }
}
    
// New - November 30, 2022 - Anita Masuskapoe
//
//      Save changes made to the fibre main, pca and general databases
//
- (IBAction)tellieConfigPushToDBAction:(id)sender {
    // --------MAIN_FIBRE DATABASE----------------------------------
    // Retrieve Fibre ID, trim active a/b
    NSString *fibre = [tellieExpertFibreSelectPb titleOfSelectedItem];
    if ([fibre length] > 0) {
        fibre = [fibre substringToIndex:[fibre length] - 1];
    }
    
    // Initialize formatter
    NSNumberFormatter *f = [[NSNumberFormatter alloc] init];
    f.numberStyle = NSNumberFormatterDecimalStyle;
               
    // Retrieve all current fibre_main settings from database
    NSMutableDictionary* mainsettings = [model returnAllTellieFibreMainSettings];
    
    // Retrieve fibre_main settings for current fibre/node
    NSMutableDictionary* currentsettings = [model returnTellieFibreMainSettings:fibre];
    
    if(![[mainsettings objectForKey:@"fibre_id"] containsObject:fibre]){
        NSLogColor([NSColor redColor], @"[TELLIE_CONFIG]: Fibre main does not include a reference to fibre: %@\n",fibre);
    }else{
        BOOL change = 0;
        NSUInteger fibreIndex = [[mainsettings objectForKey:@"fibre_id"] indexOfObject:fibre];
        
        // Check for pulse width changes
        if (![[telliePulseWidthTf stringValue] isEqualTo:[NSString stringWithFormat:@"%@",[currentsettings objectForKey:@"pulse_width"]]]){
            change = 1;
            NSNumber *pulseWidth = [f numberFromString:[telliePulseWidthTf stringValue]];
            [[mainsettings objectForKey:@"pulse_width"]  replaceObjectAtIndex:fibreIndex withObject:pulseWidth];
        }
        
        // Check for fibre delay changes
        if (![[tellieFibreDelayTf stringValue] isEqualTo:[NSString stringWithFormat:@"%@",[currentsettings objectForKey:@"fibre_delay"]]]){
            change = 1;
            NSNumber *fibreDelay = [f numberFromString:[tellieFibreDelayTf stringValue]];
            [[mainsettings objectForKey:@"fibre_delay"]  replaceObjectAtIndex:fibreIndex withObject:fibreDelay];
        }
        
        // Write changes to fibre_main
        if(change){
            [mainsettings setObject:[model stringDateFromDate:nil] forKey:@"timestamp"];
            [[model couchDBRef:model withDB:@"tellieconfig"] addDocument:mainsettings tag:@"kTellieFibreMainConfigAdded"];
            NSLog(@"New TELLIE Fibre Main settings written to tellieconfig DB.\n");
        }else{
            NSLog(@"No TELLIE Fibre Main DB changes.\n");
        }
    }
    
    // --------PCA DATABASE--------------------------------------
    NSString *triggerRate = [telliePulseFreqTf stringValue];
    NSString *noPulses = [tellieNoPulsesTf stringValue];
    NSString *triggerDelay = [tellieTriggerDelayTf stringValue];
    NSString *operationMode = [tellieExpertOperationModePb titleOfSelectedItem];
    
    NSMutableDictionary* allpcasettings = [model returnTelliePCASettings];
    
    if(![allpcasettings objectForKey:@"Slave"]){
        NSLogColor([NSColor redColor], @"[TELLIE_CONFIG]: Valid PCA config not retrieved");
        
    }else{
        BOOL pcaChange = 0;
        
        // Check for trigger rate change
        if (![triggerRate isEqualTo:[NSString stringWithFormat:@"%@",[[allpcasettings objectForKey:operationMode] objectForKey:@"trigger_rate"]]]){
            pcaChange = 1;
            [[allpcasettings objectForKey:operationMode] setValue:triggerRate forKey:@"trigger_rate"];
        }
        
        // Check for number of pulses change
        if (![noPulses isEqualTo:[NSString stringWithFormat:@"%@",[[allpcasettings objectForKey:operationMode] objectForKey:@"n_pulses"]]]){
             pcaChange = 1;
            [[allpcasettings objectForKey:operationMode] setValue:noPulses forKey:@"n_pulses"];
        }
        
        // Check for trigger delay changes
        if (![triggerDelay isEqualTo:[NSString stringWithFormat:@"%@",[[allpcasettings objectForKey:operationMode] objectForKey:@"trigger_delay"]]]){
             pcaChange = 1;
            [[allpcasettings objectForKey:operationMode] setValue:triggerDelay forKey:@"trigger_delay"];
        }
        
        // Write changes to PCA database
        if(pcaChange){
            [allpcasettings setObject:[model stringDateFromDate:nil] forKey:@"timestamp"];
            [[model couchDBRef:model withDB:@"tellieconfig"] addDocument:allpcasettings tag:@"kTelliePCAConfigAdded"];
            NSLog(@"New TELLIE PCA settings written to tellieconfig DB.\n");
        }else{
            NSLog(@"No TELLIE PCA DB changes.\n");
        }
    }
    
    // --------GENERAL DATABASE--------------------------------------
    NSString *PinTimeout = [telliePinTimeoutTf stringValue];
        
    NSMutableDictionary* allGeneralsettings = [model returnTellieGeneralSettings];
    
    if(![allGeneralsettings objectForKey:@"subrun_delay"]){
        NSLogColor([NSColor redColor], @"[TELLIE_CONFIG]: Valid General config not retrieved");
    }else{
        // Check for subrun delay change
        if (![PinTimeout isEqualTo:[NSString stringWithFormat:@"%@",[allGeneralsettings objectForKey:@"subrun_delay"]]]){
            [allGeneralsettings setObject:PinTimeout forKey:@"subrun_delay"];
            [allGeneralsettings setObject:[model stringDateFromDate:nil] forKey:@"timestamp"];
            [[model couchDBRef:model withDB:@"tellieconfig"] addDocument:allGeneralsettings tag:@"kTellieGeneralConfigAdded"];
            NSLog(@"New TELLIE General settings written to tellieconfig DB.\n");
        }else{
            NSLog(@"No TELLIE General DB changes.\n");
        }
    }
    
    [tellieConfigPushToDB setEnabled:NO];
}

- (IBAction)tellieBuildPushToDBAction:(id)sender {
    /*
     Format a dictionary into a TELLIE_RUN_PLAN document. All database
     interactions are then handled from within the models
     */

    // Make a dictionary to act as the document
    NSMutableDictionary* document = [[NSMutableDictionary alloc] init];

    // Loop over cells in matrix and find which were selected.
    NSMutableArray* nodes = [NSMutableArray arrayWithCapacity:92];
    for(int i=0; i<92; i++){
        if([[tellieBuildNodeSelection cellWithTag:i] intValue] > 0){
            [nodes addObject:[NSNumber numberWithInt:([[NSNumber numberWithInt:i] intValue] + 1)]];
        }
    }

    // Get other parameters
    NSNumber* photons = [NSNumber numberWithInteger:[tellieBuildPhotons integerValue]];
    NSNumber* noPulses = [NSNumber numberWithInteger:[tellieBuildNoPulses integerValue]];
    NSNumber* triggerDelay = [NSNumber numberWithFloat:[tellieTriggerDelayTf floatValue]];
    NSNumber* pulseRate = [NSNumber numberWithInteger:[tellieBuildRate integerValue]];
    NSString* name = [tellieBuildRunName stringValue];
    BOOL slave = YES;
    if([[tellieBuildOpMode titleOfSelectedItem] isEqualToString:@"Master"]){
        slave = NO;
    }

    [document setObject:@"TELLIE_RUN_PLAN" forKey:@"type"];
    [document setObject:@"" forKey:@"index"];
    [document setObject:@"" forKey:@"comment"];
    [document setObject:[model stringDateFromDate:nil] forKey:@"timestamp"];
    [document setObject:[NSNumber numberWithInt:0] forKey:@"version"];
    [document setObject:[NSNumber numberWithInt:0] forKey:@"pass"];
    [document setObject:photons forKey:@"photons_per_pulse"];
    [document setObject:noPulses forKey:@"trigger_per_node"];
    [document setObject:triggerDelay forKey:@"trigger_delay"];
    [document setObject:pulseRate forKey:@"trigger_rate"];
    [document setObject:nodes forKey:@"nodes"];
    [document setObject:[NSNumber numberWithBool:slave] forKey:@"slave_mode"];
    [document setObject:name forKey:@"name"];

    [[model couchDBRef:model withDB:@"telliedb"] addDocument:document tag:@"kTellieRunPlanAdded"];

    [tellieBuildPushToDB setEnabled:NO];
    [document release];
}

//////////////////////////
// AMELLIE actions
//////////////////////////
- (IBAction)amellieFireAction:(id)sender {
    ////////////
    // Check a run isn't ongoing
    if([model ellieFireFlag]){
        NSLogColor([NSColor redColor], @"[AMELLIE]: Fire button will not work while an ELLIE run is underway\n");
        return;
    }

    [amellieFireButton setEnabled:NO];
    [amellieStopButton setEnabled:YES];
    [[NSNotificationCenter defaultCenter] postNotificationName:ORAMELLIERunStartNotification object:nil userInfo:[self guiFireSettings]];
    [amellieValidationStatusTf setStringValue:@""];
}

- (IBAction)amellieStopAction:(id)sender {
    [model stopTellieRun];
}


////////////////////////////////////////////////////////
//
// TELLIE Validation button functions
//
////////////////////////////////////////////////////////
-(IBAction)tellieExpertValidateSettingsAction:(id)sender
{
    [self setGuiFireSettings:nil];
    [tellieTriggerDelayTf.window makeFirstResponder:nil];
    [tellieFibreDelayTf.window makeFirstResponder:nil];
    [telliePulseWidthTf.window makeFirstResponder:nil];
    [telliePulseFreqTf.window makeFirstResponder:nil];
    [tellieChannelTf.window makeFirstResponder:nil];
    [tellieNoPulsesTf.window makeFirstResponder:nil];
    [tellieExpertOperationModePb.window makeFirstResponder:nil];

    //Check if fibre mapping has been loaded from the tellieDB
    if(![model tellieNodeMapping]){
        [model loadTELLIEStaticsFromDB];
    }
    //If still can't get reference, return
    if(![model tellieNodeMapping]){
        NSLogColor([NSColor redColor], @"[TELLIE]: Cannot connect to couchdb database\n");
        return;
    }
    
    NSString* msg = nil;
    NSMutableArray* msgs = [NSMutableArray arrayWithCapacity:7];
    NSLog(@"---------------------------- Tellie Validation messages ----------------------------\n");
    msg = [self validateTellieTriggerDelay:[tellieTriggerDelayTf stringValue]];
    if(msg){
        [msgs insertObject:msg atIndex:0];
    } else {
        [msgs insertObject:[NSNull null] atIndex:0];
    }
    
    msg = [self validateTellieFibreDelay:[tellieFibreDelayTf stringValue]];
    if(msg){
        [msgs insertObject:msg atIndex:1];
    } else {
        [msgs insertObject:[NSNull null] atIndex:1];
    }

    msg = [self validateTelliePulseWidth:[telliePulseWidthTf stringValue]];
    if(msg){
        [msgs insertObject:msg atIndex:2];
    } else {
        [msgs insertObject:[NSNull null] atIndex:2];
    }

    // Get pulse height from tellieConfig-> general DB
    NSMutableDictionary* gensettings = [model returnTellieGeneralSettings];
    
    msg = [self validateTelliePulseHeight:[[gensettings valueForKey:@"pulse_height"] stringValue]];
    if(msg){
        [msgs insertObject:msg atIndex:3];
    } else {
        [msgs insertObject:[NSNull null] atIndex:3];
    }

    msg = [self validateTelliePulseFreq:[telliePulseFreqTf stringValue]];
    if(msg){
        [msgs insertObject:msg atIndex:4];
    } else {
        [msgs insertObject:[NSNull null] atIndex:4];
    }

    msg = [self validateTellieChannel:[tellieChannelTf stringValue]];
    if(msg){
        [msgs insertObject:msg atIndex:5];
    } else {
        [msgs insertObject:[NSNull null] atIndex:5];
    }

    msg = [self validateTellieNoPulses:[tellieNoPulsesTf stringValue]];
    if(msg){
        [msgs insertObject:msg atIndex:6];
    } else {
        [msgs insertObject:[NSNull null] atIndex:6];
    }
    
    msg = [self validateTellieSubrunDelay:[telliePinTimeoutTf stringValue]];
    if(msg){
        [msgs insertObject:msg atIndex:7];
    } else {
        [msgs insertObject:[NSNull null] atIndex:7];
    }

    // Remove any null objects
    for(int i = 0; i < [msgs count]; i++){
        if([msgs objectAtIndex:i] == [NSNull null]){
            [msgs removeObject:[msgs objectAtIndex:i]];
        }
    }
    
    // Initialize formatter
    NSNumberFormatter *f = [[NSNumberFormatter alloc] init];
    f.numberStyle = NSNumberFormatterDecimalStyle;
    
    // Check if validation passed
    if([msgs count] == 0){
        NSLog(@"[TELLIE]: Expert settings are valid\n");
        //Set backgrounds back to white
        [tellieChannelTf setBackgroundColor:[NSColor whiteColor]];
        [telliePulseWidthTf setBackgroundColor:[NSColor whiteColor]];
        [tellieFibreDelayTf setBackgroundColor:[NSColor whiteColor]];
        [telliePulseFreqTf setBackgroundColor:[NSColor whiteColor]];
        [tellieNoPulsesTf setBackgroundColor:[NSColor whiteColor]];
        [tellieTriggerDelayTf setBackgroundColor:[NSColor whiteColor]];
        [telliePinTimeoutTf setBackgroundColor:[NSColor whiteColor]];
                        
        // Make settings dict to pass to fire method
        NSMutableDictionary* settingsDict = [NSMutableDictionary dictionaryWithCapacity:100];
        
        // Pulse seperation
        float pulseSeparation = 1000.*(1./[telliePulseFreqTf floatValue]); // TELLIE accepts pulse rate in ms
        NSString *pulseSeparationString = [[NSNumber numberWithFloat:pulseSeparation] stringValue];
        // Fibre
        NSString *ActiveFibre = [tellieExpertFibreSelectPb titleOfSelectedItem];
        NSString *fibre = @"";
        if ([ActiveFibre length] > 0) {
            fibre = [ActiveFibre substringToIndex:[ActiveFibre length] - 1];
        }
                
        [settingsDict setValue:fibre forKey:@"fibre"];
        [settingsDict setValue:[NSNumber numberWithInteger:[tellieChannelTf integerValue]]  forKey:@"channel"];
        
        [settingsDict setValue:[tellieExpertOperationModePb titleOfSelectedItem] forKey:@"run_mode"];
        [settingsDict setValue:[NSNumber numberWithInteger:[telliePulseWidthTf integerValue]] forKey:@"pulse_width"];
        [settingsDict setValue:[f numberFromString:pulseSeparationString] forKey:@"pulse_separation"];
        [settingsDict setValue:[NSNumber numberWithInteger:[tellieNoPulsesTf integerValue]] forKey:@"number_of_shots"];
        [settingsDict setValue:[NSNumber numberWithInteger:[tellieTriggerDelayTf integerValue]] forKey:@"trigger_delay"];
        [settingsDict setValue:[NSNumber numberWithFloat:[tellieFibreDelayTf floatValue]] forKey:@"fibre_delay"];                
        [settingsDict setValue:[NSNumber numberWithInteger:[[gensettings valueForKey:@"pulse_height"] integerValue]] forKey:@"pulse_height"];
        [settingsDict setValue:[NSNumber numberWithInteger:[telliePinTimeoutTf integerValue]] forKey:@"pin_delay"];
        [self setGuiFireSettings:settingsDict];
        
        [tellieExpertFireButton setEnabled:YES];
        [tellieConfigPushToDB setEnabled:YES];
        [tellieExpertValidationStatusTf setStringValue:@"Settings are valid. Fire away!"];
    } else {
        [tellieExpertValidationStatusTf setStringValue:@"Validation issues found. See orca log for full description.\n"];
    }
    NSLog(@"---------------------------------------------------------------------------------------------\n");
}

-(IBAction)tellieGeneralValidateSettingsAction:(id)sender
{
    [self setGuiFireSettings:nil];
    [tellieGeneralNodeTf.window makeFirstResponder:nil];
    [tellieGeneralNoPulsesTf.window makeFirstResponder:nil];
    [tellieGeneralPhotonsTf.window makeFirstResponder:nil];
    [tellieGeneralTriggerDelayTf.window makeFirstResponder:nil];
    [tellieGeneralFreqTf.window makeFirstResponder:nil];
    [tellieGeneralOperationModePb.window makeFirstResponder:nil];

    //Check if fibre mapping has been loaded from the tellieDB
    if(![model tellieNodeMapping]){
        [model loadTELLIEStaticsFromDB];
    }
    //If still can't get reference, return
    if(![model tellieNodeMapping]){
        NSLogColor([NSColor redColor], @"[TELLIE]: Cannot connect to couchdb database\n");
        return;
    }
    
    NSString* msg = nil;
    NSMutableArray* msgs = [NSMutableArray arrayWithCapacity:4];

    ///////////////
    // Run checks
    NSLog(@"---------------------------- Tellie Validation messages ----------------------------\n");
    //msg = [self validateGeneralTellieNode:[tellieGeneralNodeTf stringValue]];
    //if(msg){
    //    [msgs insertObject:msg atIndex:0];
    //} else {
    //  [msgs insertObject:[NSNull null] atIndex:0];
    //}

    msg = [self validateGeneralTellieNoPulses:[tellieGeneralNoPulsesTf stringValue]];
    if(msg){
        [msgs insertObject:msg atIndex:0];
    } else {
        [msgs insertObject:[NSNull null] atIndex:0];
    }

    msg = [self validateGeneralTelliePhotons:[tellieGeneralPhotonsTf stringValue]];
    if(msg){
        [msgs insertObject:msg atIndex:1];
    } else {
        [msgs insertObject:[NSNull null] atIndex:1];
    }

    msg = [self validateGeneralTellieTriggerDelay:[tellieGeneralTriggerDelayTf stringValue]];
    if(msg){
        [msgs insertObject:msg atIndex:2];
    } else {
        [msgs insertObject:[NSNull null] atIndex:2];
    }

    msg = [self validateGeneralTelliePulseFreq:[tellieGeneralFreqTf stringValue]];
    if(msg){
        [msgs insertObject:msg atIndex:3];
    } else {
        [msgs insertObject:[NSNull null] atIndex:3];
    }
    
    // Calculate settings and check any issues in
    BOOL inSlave = YES;
    if([[tellieGeneralOperationModePb titleOfSelectedItem] isEqualToString:@"Master"]){
        inSlave = NO;
    }
    
    NSMutableDictionary* settings = [model returnTellieFireCommands:[tellieGeneralFibreSelectPb titleOfSelectedItem] withNPhotons:[tellieGeneralPhotonsTf integerValue] withFireFrequency:[tellieGeneralFreqTf integerValue] withNPulses:[tellieGeneralNoPulsesTf integerValue] withTriggerDelay:[tellieGeneralTriggerDelayTf integerValue] inSlave:inSlave isAMELLIE:NO];
    
    if(settings){
        [self setGuiFireSettings:settings];
    } else if(settings == nil){
        [msgs insertObject:@"[TELLIE]: Settings dict not created\n" atIndex:4];
    }
    
    // Remove any null objects
    for(int i = 0; i < [msgs count]; i++){
        if([msgs objectAtIndex:i] == [NSNull null]){
            [msgs removeObject:[msgs objectAtIndex:i]];
        }
    }
    
    // Check validations passed
    if([msgs count] == 0){
        NSLog(@"[TELLIE]: Expert settings are valid\n");
        [tellieGeneralValidationStatusTf setStringValue:@"Settings are valid. Fire away!"];
        [tellieGeneralFireButton setEnabled:YES];
    } else {
        //NSLog(@"Invalidity problems in Tellie general gui: %@\n", msgs);
        [tellieGeneralValidationStatusTf setStringValue:@"Validation issues found. See orca log for full description.\n"];
    }
    NSLog(@"---------------------------------------------------------------------------------------------\n");
}

-(void) tellieBuildValidateAction:(id)sender
{
    [model loadTELLIERunPlansFromDB];
    [tellieBuildNoPulses.window makeFirstResponder:nil];
    [tellieBuildPhotons.window makeFirstResponder:nil];
    [tellieBuildRate.window makeFirstResponder:nil];
    [tellieBuildTrigDelay.window makeFirstResponder:nil];

    //Check if fibre mapping has been loaded from the tellieDB
    if(![model tellieNodeMapping]){
        [model loadTELLIEStaticsFromDB];
    }
    //If still can't get reference, return
    if(![model tellieNodeMapping]){
        NSLogColor([NSColor redColor], @"[TELLIE]: Cannot connect to couchdb database\n");
        return;
    }
    [NSThread sleepForTimeInterval:1.0f];

    NSString* msg = nil;
    NSMutableArray* msgs = [NSMutableArray arrayWithCapacity:6];

    ///////////////
    // Run checks
    NSLog(@"---------------------------- Tellie Validation messages ----------------------------\n");

    msg = [self validateGeneralTellieNoPulses:[tellieBuildNoPulses stringValue]];
    if(msg){
        [msgs insertObject:msg atIndex:0];
    } else {
        [msgs insertObject:[NSNull null] atIndex:0];
    }

    msg = [self validateGeneralTelliePhotons:[tellieBuildPhotons stringValue]];
    if(msg){
        [msgs insertObject:msg atIndex:1];
    } else {
        [msgs insertObject:[NSNull null] atIndex:1];
    }

    msg = [self validateGeneralTelliePulseFreq:[tellieBuildRate stringValue]];
    if(msg){
        [msgs insertObject:msg atIndex:2];
    } else {
        [msgs insertObject:[NSNull null] atIndex:2];
    }

    msg = [self validateGeneralTellieTriggerDelay:[tellieBuildTrigDelay stringValue]];
    if(msg){
        [msgs insertObject:msg atIndex:3];
    } else {
        [msgs insertObject:[NSNull null] atIndex:3];
    }

    BOOL safety_check = [model photonIntensityCheck:[tellieBuildPhotons integerValue] atFrequency:[tellieBuildRate integerValue]];
    if(safety_check == NO){
        msg = @"Requested photon output is not detector safe at requested frequncy\n";
        NSLog(@"%@",msg);
        [msgs insertObject:msg atIndex:4];
    } else {
        [msgs insertObject:[NSNull null] atIndex:4];
    }

    ///////////////////////////////////
    // Check file name against database
    msg = nil;
    for(NSString* name in [model tellieRunNames]){
        if([name isEqualToString:[tellieBuildRunName stringValue]]){
            msg = @"[TELLIE]: Run plan name already exists on database\n";
            NSLog(msg);
        }
    }
    if(msg){
        [msgs insertObject:msg atIndex:5];
    } else {
        [msgs insertObject:[NSNull null] atIndex:5];
    }

    //////////////////////////
    // Remove any null objects
    for(int i = 0; i < [msgs count]; i++){
        if([msgs objectAtIndex:i] == [NSNull null]){
            [msgs removeObject:[msgs objectAtIndex:i]];
        }
    }

    // Check validations passed
    if([msgs count] == 0){
        NSLog(@"[TELLIE]: Build custom sequence - settings are valid\n");
        [tellieBuildPushToDB setEnabled:YES];
    } else {
        [tellieBuildPushToDB setEnabled:NO];
        NSLog(@"[TELLIE]: Build custom sequence - settings invalid please resolve issues.\n");
    }
    NSLog(@"---------------------------------------------------------------------------------------------\n");
}

-(IBAction)amellieValidateSettingsAction:(id)sender
{
    [self setGuiFireSettings:nil];
    [amellieTriggerDelayTf.window makeFirstResponder:nil];
    [amellieFibreDelayTf.window makeFirstResponder:nil];
    [amelliePulseWidthTf.window makeFirstResponder:nil];
    [amelliePulseHeightTf.window makeFirstResponder:nil];
    [amelliePulseFreqTf.window makeFirstResponder:nil];
    [amellieNoPulsesTf.window makeFirstResponder:nil];
    [amellieNodeSelectPb.window makeFirstResponder:nil];
    [amellieOperationModePb.window makeFirstResponder:nil];

    //Check if fibre mapping has been loaded from the amellieDB
    if(![model amellieNodeMapping]){
        [model loadAMELLIEStaticsFromDB];
    }
    //If still can't get reference, return
    if(![model amellieNodeMapping]){
        NSLogColor([NSColor redColor], @"[TELLIE]: Cannot connect to couchdb database\n");
        return;
    }

    NSString* msg = nil;
    NSMutableArray* msgs = [NSMutableArray arrayWithCapacity:7];
    NSLog(@"---------------------------- Amellie Validation messages ----------------------------\n");
    msg = [self validateTellieTriggerDelay:[amellieTriggerDelayTf stringValue]];
    if(msg){
        [msgs insertObject:msg atIndex:0];
    } else {
        [msgs insertObject:[NSNull null] atIndex:0];
    }

    msg = [self validateTellieFibreDelay:[amellieFibreDelayTf stringValue]];
    if(msg){
        [msgs insertObject:msg atIndex:1];
    } else {
        [msgs insertObject:[NSNull null] atIndex:1];
    }

    msg = [self validateTelliePulseWidth:[amelliePulseWidthTf stringValue]];
    if(msg){
        [msgs insertObject:msg atIndex:2];
    } else {
        [msgs insertObject:[NSNull null] atIndex:2];
    }

    msg = [self validateTelliePulseHeight:[amelliePulseHeightTf stringValue]];
    if(msg){
        [msgs insertObject:msg atIndex:3];
    } else {
        [msgs insertObject:[NSNull null] atIndex:3];
    }

    msg = [self validateTelliePulseFreq:[amelliePulseFreqTf stringValue]];
    if(msg){
        [msgs insertObject:msg atIndex:4];
    } else {
        [msgs insertObject:[NSNull null] atIndex:4];
    }

    msg = [self validateTellieNoPulses:[amellieNoPulsesTf stringValue]];
    if(msg){
        [msgs insertObject:msg atIndex:5];
    } else {
        [msgs insertObject:[NSNull null] atIndex:5];
    }

    // Remove any null objects
    for(int i = 0; i < [msgs count]; i++){
        if([msgs objectAtIndex:i] == [NSNull null]){
            [msgs removeObject:[msgs objectAtIndex:i]];
        }
    }

    // Check if validation passed
    if([msgs count] == 0){
        NSLog(@"[AMELLIE]: fire settings are valid\n");
        //Set backgrounds back to white
        [amelliePulseWidthTf setBackgroundColor:[NSColor whiteColor]];
        [amelliePulseFreqTf setBackgroundColor:[NSColor whiteColor]];
        [amelliePulseHeightTf setBackgroundColor:[NSColor whiteColor]];
        [amellieFibreDelayTf setBackgroundColor:[NSColor whiteColor]];
        [amellieTriggerDelayTf setBackgroundColor:[NSColor whiteColor]];
        [amellieNoPulsesTf setBackgroundColor:[NSColor whiteColor]];
        // Make settings dict to pass to fire method
        NSString* panel_name = [NSString stringWithFormat:@"panel_%@", [amellieNodeSelectPb titleOfSelectedItem]];
        NSDictionary* angle_to_fibre = [[model amellieNodeMapping] objectForKey:panel_name];
        NSString* fibre = [angle_to_fibre objectForKey:[amellieAngleSelectPb titleOfSelectedItem]];
        // When someone changes the Fibre selection, automatically update the channel field
        [amellieChannelTf setStringValue:[NSString stringWithFormat:@"%@",[model calcAmellieChannelForFibre:fibre]]];
        float pulseSeparation = 1000.*(1./[amelliePulseFreqTf floatValue]); // TELLIE accepts pulse rate in ms
        NSMutableDictionary* settingsDict = [NSMutableDictionary dictionaryWithCapacity:100];
        [settingsDict setValue:fibre forKey:@"fibre"];
        [settingsDict setValue:[NSNumber numberWithInteger:[amellieChannelTf integerValue]] forKey:@"channel"];
        [settingsDict setValue:[amellieOperationModePb titleOfSelectedItem] forKey:@"run_mode"];
        [settingsDict setValue:[NSNumber numberWithInteger:[amelliePulseWidthTf integerValue]] forKey:@"pulse_width"];
        [settingsDict setValue:[NSNumber numberWithFloat:pulseSeparation] forKey:@"pulse_separation"];
        [settingsDict setValue:[NSNumber numberWithInteger:[amellieNoPulsesTf integerValue]] forKey:@"number_of_shots"];
        [settingsDict setValue:[NSNumber numberWithInteger:[amellieTriggerDelayTf integerValue]] forKey:@"trigger_delay"];
        [settingsDict setValue:[NSNumber numberWithFloat:[amellieFibreDelayTf floatValue]] forKey:@"fibre_delay"];
        [settingsDict setValue:[NSNumber numberWithInteger:[amelliePulseHeightTf integerValue]] forKey:@"pulse_height"];
        [self setGuiFireSettings:settingsDict];
        [amellieFireButton setEnabled:YES];
        [amellieValidationStatusTf setStringValue:@"Settings are valid. Fire away!"];
    } else {
        [amellieValidationStatusTf setStringValue:@"Validation issues found. See orca log for full description.\n"];
    }
    NSLog(@"---------------------------------------------------------------------------------------------\n");
}


////////////////////////////////////////////
// Delagate funcs waiting to observe edits
////////////////////////////////////////////
-(void)controlTextDidBeginEditing:(NSNotification *)note {
            
    if([note object] == tellieExpertNodeTf){
        [tellieChannelTf setStringValue:@""];
        [tellieTriggerDelayTf setStringValue:@""];
        [telliePulseFreqTf setStringValue:@""];
        [telliePulseWidthTf setStringValue:@""];
        [tellieNoPulsesTf setStringValue:@""];
        [tellieFibreDelayTf setStringValue:@""];
        [telliePinTimeoutTf setStringValue:@""];
        [tellieExpertFireButton setEnabled:NO];
        [tellieExpertValidateSettingsButton setEnabled:NO];
        [tellieConfigPushToDB setEnabled:NO];
        [tellieExpertFibresTf setStringValue:@""];
        [tellieExpertFibreSelectPb removeAllItems];
        [tellieExpertFibreSelectPb setEnabled:NO];
        [tellieExpertOperationModePb setEnabled:NO];
        
    }
    
    [tellieExpertFireButton setEnabled:NO];
    [tellieGeneralValidationStatusTf setStringValue:@""];

    [tellieGeneralFireButton setEnabled:NO];
    [tellieExpertValidationStatusTf setStringValue:@""];

    [tellieBuildPushToDB setEnabled:NO];
}

-(void)controlTextDidEndEditing:(NSNotification *)note {
    
    /* This method catches notifications sent when a control with editable text
     finishes editing a field.
     
     Validation checks are made on the new text input dependent on which field was
     edited.
     */
    //Get a reference to whichever field was changed
    //Check if fibre mapping has been loaded from the tellieDB

    if(![model tellieNodeMapping]){
        [model loadTELLIEStaticsFromDB];
    }
    if(![model amellieFibreMapping]){
        [model loadAMELLIEStaticsFromDB];
    }

    //If still can't get reference, return
    if(![model tellieNodeMapping]){
        NSLogColor([NSColor redColor], @"[TELLIE]: Cannot access node mapping, it's likely the code had been unable to connect to couchdb database\n");
        return;
    }

    //If still can't get reference, return
    if(![model amellieFibreMapping]){
        NSLogColor([NSColor redColor], @"[AMELLIE]: Cannot access node mapping, it's likely the code had been unable to connect to couchdb database\n");
        return;
    }
    
    NSTextField * editedField = [note object];
    NSString* currentString = [editedField stringValue];
    
    NSString* expertMsg = nil;
    NSString* generalMsg = nil;
    NSString* buildMsg = nil;
    NSString* amellieMsg = nil;

    BOOL gotInside = NO;

    //Make sure background gets drawn
    [editedField setDrawsBackground:YES];

    /////////////////////////////////////////////////////////////
    //check if this notification originated from the expert tab
    //
    if([note object] == tellieExpertNodeTf){
        expertMsg = [self validateExpertTellieNode:currentString];
        gotInside = YES;
    } else if([note object] == tellieTriggerDelayTf){
        expertMsg = [self validateTellieTriggerDelay:currentString];
        gotInside = YES;
    } else if ([note object] == tellieFibreDelayTf){
        expertMsg = [self validateTellieFibreDelay:currentString];
        gotInside = YES;
    } else if ([note object] == telliePulseFreqTf){
        expertMsg = [self validateTelliePulseFreq:currentString];
        gotInside = YES;
    } else if ([note object] == telliePulseWidthTf){
        expertMsg = [self validateTelliePulseWidth:currentString];
        gotInside = YES;
    } else if ([note object] == tellieNoPulsesTf){
        expertMsg = [self validateTellieNoPulses:currentString];
        gotInside = YES;
    } else if ([note object] == telliePinTimeoutTf){
        expertMsg = [self validateTellieSubrunDelay:currentString];
        gotInside = YES;
    }
    
    if(expertMsg){
        [tellieExpertFireButton setEnabled:NO];
        [tellieConfigPushToDB setEnabled:NO];
        [tellieExpertValidationStatusTf setStringValue:expertMsg];
        [editedField setBackgroundColor:[NSColor orangeColor]];
        [editedField setNeedsDisplay:YES];
        return;
    } else if(expertMsg == nil && gotInside == YES){
        [tellieExpertFireButton setEnabled:NO];
        [tellieConfigPushToDB setEnabled:NO];
        [tellieExpertValidationStatusTf setStringValue:@""];
        [editedField setBackgroundColor:[NSColor whiteColor]];
        [editedField setNeedsDisplay:YES];
        return;
    }
    
    /////////////////////////////////////////////////////////////
    //check if this notification originated from the general tab

    //Re-set got inside.
    gotInside = NO;
    
    if([note object] == tellieGeneralNodeTf){
        generalMsg = [self validateGeneralTellieNode:currentString];
        gotInside = YES;
    } else if ([note object] == tellieGeneralFreqTf){
        generalMsg = [self validateGeneralTelliePulseFreq:currentString];
        gotInside = YES;
    } else if ([note object] == tellieGeneralNoPulsesTf){
        generalMsg = [self validateGeneralTellieNoPulses:currentString];
        gotInside = YES;
    } else if ([note object] == tellieGeneralPhotonsTf){
        generalMsg = [self validateGeneralTelliePhotons:currentString];
        gotInside = YES;
    } else if ([note object] == tellieGeneralTriggerDelayTf){
        generalMsg = [self validateTellieTriggerDelay:currentString];
        gotInside = YES;
    }
    
    // If we get a message back, change textField color and pass validation status
    if(generalMsg){
        [tellieGeneralFireButton setEnabled:NO];
        [tellieGeneralValidationStatusTf setStringValue:generalMsg];
        [editedField setBackgroundColor:[NSColor orangeColor]];
        [editedField setNeedsDisplay:YES];
        return;
    } else if(generalMsg == nil && gotInside == YES){
        [tellieGeneralFireButton setEnabled:NO];
        [tellieGeneralValidationStatusTf setStringValue:@""];
        [editedField setBackgroundColor:[NSColor whiteColor]];
        [editedField setNeedsDisplay:YES];
        return;
    }

    /////////////////////////////////////////////////////////////
    // check if this notification originated from tellie run plan tab

    //Re-set got inside.
    gotInside = NO;

    if([note object] == tellieBuildPhotons){
        buildMsg = [self validateGeneralTelliePhotons:currentString];
        gotInside = YES;
    } else if ([note object] == tellieBuildNoPulses){
        buildMsg = [self validateGeneralTellieNoPulses:currentString];
        gotInside = YES;
    } else if ([note object] == tellieBuildRate) {
        buildMsg = [self validateGeneralTelliePulseFreq:currentString];
        gotInside = YES;
    } else if ([note object] == tellieBuildTrigDelay){
        buildMsg = [self validateGeneralTellieTriggerDelay:currentString];
        gotInside = YES;
    }

    if(buildMsg){
        [tellieBuildPushToDB setEnabled:NO];
        [editedField setBackgroundColor:[NSColor orangeColor]];
        [editedField setNeedsDisplay:YES];
        return;
    } else if(buildMsg == nil && gotInside == YES){
        [tellieBuildPushToDB setEnabled:NO];
        [editedField setBackgroundColor:[NSColor whiteColor]];
        [editedField setNeedsDisplay:YES];
        return;
    }

    /////////////////////////////////////////////////////////////
    // check if this notification originated from the AMELLIE tab

    //Re-set got inside.
    gotInside = NO;

    if([note object] == amellieTriggerDelayTf){
        amellieMsg = [self validateTellieTriggerDelay:currentString];
        gotInside = YES;
    } else if ([note object] == amellieFibreDelayTf){
        amellieMsg = [self validateTellieFibreDelay:currentString];
        gotInside = YES;
    } else if ([note object] == amelliePulseFreqTf){
        amellieMsg = [self validateTelliePulseFreq:currentString];
        gotInside = YES;
    } else if ([note object] == amelliePulseHeightTf){
        amellieMsg = [self validateTelliePulseHeight:currentString];
        gotInside = YES;
    } else if ([note object] == amelliePulseWidthTf){
        amellieMsg = [self validateTelliePulseWidth:currentString];
        gotInside = YES;
    } else if ([note object] == amellieNoPulsesTf){
        amellieMsg = [self validateTellieNoPulses:currentString];
        gotInside = YES;
    }

    if(amellieMsg){
        [amellieFireButton setEnabled:NO];
        [amellieValidationStatusTf setStringValue:amellieMsg];
        [editedField setBackgroundColor:[NSColor orangeColor]];
        [editedField setNeedsDisplay:YES];
        return;
    } else if(amellieMsg == nil && gotInside == YES){
        [amellieFireButton setEnabled:NO];
        [amellieValidationStatusTf setStringValue:@""];
        [editedField setBackgroundColor:[NSColor whiteColor]];
        [editedField setNeedsDisplay:YES];
        return;
    }
}

/////////////////////////////////////////////
// Validation functions for each tab / field
/////////////////////////////////////////////

///////////////
// General gui
///////////////
-(NSString*)validateGeneralTellieNode:(NSString *)currentText
{
    //Check if fibre mapping has been loaded from the tellieDB
    if(![model tellieNodeMapping]){
        [model loadTELLIEStaticsFromDB];
    }
    
    //Clear out any old data
    [tellieGeneralFibreSelectPb removeAllItems];
    [tellieGeneralFibreSelectPb setEnabled:NO];

    //Use already implemented function in the ELLIEModel to check if Fibre is patched.
    NSMutableDictionary* nodeInfo = [[model tellieNodeMapping] objectForKey:[NSString stringWithFormat:@"panel_%d",[currentText intValue]]];
    if(nodeInfo == nil){
        NSString* msg = [NSString stringWithFormat:@"[TELLIE_VALIDATION]: Node map does not include a reference to node: %@\n", currentText];
        NSLog(msg);
        return msg;
    }
    
    BOOL check = NO;
    for(NSString* key in nodeInfo){
        if([[nodeInfo objectForKey:key] intValue] ==  0 || [[nodeInfo objectForKey:key] intValue] ==  1){
            [tellieGeneralFibreSelectPb addItemWithTitle:key];
            check = YES;
        }
    }
    
    if(check == NO){
        NSString* msg = [NSString stringWithFormat:@"[TELLIE_VALIDATION]: No active fibres available at node: %@\n", currentText];
        NSLog(msg);
        [tellieGeneralFibreSelectPb removeAllItems];
        [tellieGeneralFibreSelectPb setEnabled:NO];
        return msg;
    }
    
    NSString* optimalFibre = [model calcTellieFibreForNode:[currentText intValue]];
    [tellieGeneralFibreSelectPb selectItemWithTitle:optimalFibre];
    [tellieGeneralFibreSelectPb setEnabled:YES];
    return nil;
}

-(NSString*)validateGeneralTelliePhotons:(NSString *)currentText
{
    NSScanner* scanner = [NSScanner scannerWithString:currentText];
    int photons = [currentText intValue];
    int maxPhotons = 1e5;
    
    NSString* msg = @"[TELLIE_VALIDATION]: Valid Photons per pulse range: 0-1e5\n";
    if (![scanner scanInt:nil]){
        NSLog(msg);
        return msg;
    } else if(photons < 0){
        NSLog(msg);
        return msg;
    } else if(photons > maxPhotons){
        NSLog(msg);
        return msg;
    }
    return nil;
}

-(NSString*)validateGeneralTelliePulseFreq:(NSString *)currentText
{
    // Constraints are the same for both tabs
    NSString* msg = [self validateTelliePulseFreq:currentText];
    if(msg){
        return msg;
    }
    return nil;
}

-(NSString*)validateGeneralTellieNoPulses:(NSString *)currentText
{
    // Constraints are the same for both tabs
    return [self validateTellieNoPulses:currentText];
}

-(NSString*)validateGeneralTellieTriggerDelay:(NSString *)currentText
{
    //This will need updateing. I need to ask Eric about the specs of Tubii's trigger delay.
    return [self validateTellieTriggerDelay:currentText];
}

/////////////
//Expert gui
/////////////
-(NSString*)validateExpertTellieNode:(NSString *)currentText
{
    if(![[model tellieFibreMainSettings] objectForKey:[NSString stringWithFormat:@"node"]]){
        NSLogColor([NSColor redColor], @"[TELLIE_CONFIG]: Valid Fibre main config not retrieved");
    }
    
    // Deselect the node text field
    [tellieExpertNodeTf resignFirstResponder];
            
    //Clear out any old data
    [tellieExpertFibreSelectPb removeAllItems];
    [tellieExpertFibreSelectPb setEnabled:NO];
    
    //Get Fibres for this node
    NSInteger node = [currentText integerValue];
    NSMutableArray* nodeInfo = [model returnTellieNodeFibres:node];
    
    if(nodeInfo == nil){
        NSString* msg = [NSString stringWithFormat:@"[TELLIE_VALIDATION]: Node map does not include a reference to node: %@\n", currentText];
        NSLog(msg);
        return msg;
    }
    
    if([nodeInfo count] > 0){
        for(NSString* object in nodeInfo){
            [tellieExpertFibreSelectPb addItemWithTitle:[NSString stringWithFormat:object]];
        }
        [tellieExpertFibreSelectPb setEnabled:YES];
        
        if([nodeInfo count] > 1){
            [tellieExpertFibresTf setStringValue:@"*Multiple Fibres"];
        }
    }
    if([nodeInfo count] == 0){
        NSString* msg = [NSString stringWithFormat:@"[TELLIE_VALIDATION]: No active fibres available at node: %@\n", currentText];
        [tellieExpertFibreSelectPb removeAllItems];
        [tellieExpertFibreSelectPb setEnabled:NO];
        NSLog(msg);
        return msg;
    }
    return nil;
}

-(NSString*)validateTellieChannel:(NSString *)currentText
{
    NSScanner* scanner = [NSScanner scannerWithString:currentText];
    int currentChannelNumber = [currentText intValue];
    int minimumChannelNumber = 1;
    int maxmiumChannelNumber = 95;
    
    NSString* msg = [NSString stringWithFormat:@"[ELLIE_VALIDATION]: Valid channel numbers are 1-95\n"];
    if(currentChannelNumber  > maxmiumChannelNumber){
        NSLog(msg);
        return msg;
    } else if (currentChannelNumber  < minimumChannelNumber){
        NSLog(msg);
        return msg;
    } else if (![scanner scanInt:nil]){
        NSLog(msg);
        return msg;
    }
    
    return nil;
}

-(NSString*)validateTelliePulseWidth:(NSString *)currentText
{
    NSScanner* scanner = [NSScanner scannerWithString:currentText];
    int currentValue = [currentText intValue];
    int minimumValue = 0;
    int maxmiumValue = 16383;
    
    NSString* msg = @"[ELLIE_VALIDATION]: Valid pulse width settings: 0-16383 in integer steps\n";
    if(currentValue  > maxmiumValue){
        NSLog(msg);
        return msg;
    } else if (currentValue  < minimumValue){
        NSLog(msg);
        return msg;
    } else if (![scanner scanInt:nil]){
        NSLog(msg);
        return msg;
    }

    return nil;
}

-(NSString*)validateTelliePulseHeight:(NSString *)currentText
{
    NSScanner* scanner = [NSScanner scannerWithString:currentText];
    int currentValue = [currentText intValue];
    int minimumValue = 0;
    int maxmiumValue = 16383;
    
    NSString* msg = @"[ELLIE_VALIDATION]: Valid pulse height settings: 0-16383 in integer steps\n";
    if(currentValue  > maxmiumValue){
        NSLog(msg);
        return msg;
    } else if (currentValue  < minimumValue){
        NSLog(msg);
        return msg;
    } else if (![scanner scanInt:nil]){
        NSLog(msg);
        return msg;
    }
    
    return nil;
}


-(NSString*)validateTelliePulseFreq:(NSString *)currentText
{
    NSScanner* scanner = [NSScanner scannerWithString:currentText];
    float frequency = [currentText floatValue];
    float maxFreq = 1e4;

    NSString* msg = @"[ELLIE_VALIDATION]: Valid frequency settings: 1-10000Hz\n";
    if (![scanner scanFloat:nil]){
        NSLog(msg);
        return msg;
    } else if(frequency  > maxFreq){
        NSLog(msg);
        return msg;
    } else if (frequency < 1) {
        NSLog(msg);
        return msg;
    }
    return nil;
}

-(NSString*)validateTellieFibreDelay:(NSString *)currentText
{
    NSScanner* scanner = [NSScanner scannerWithString:currentText];
    float fibreDelayNumber = [currentText floatValue];
    float minimumFibreDelay = 0;                    //in ns
    float maxmiumFibreDelay = 63.75;                //in ns
    
    NSString* msg = @"[ELLIE_VALIDATION]: Valid fibre delay settings: 0-63.75 ns.\n";
    if (![scanner scanFloat:nil]){
        NSLog(msg);
        return msg;
    } else if(fibreDelayNumber  > maxmiumFibreDelay){
        NSLog(msg);
        return msg;
    } else if (fibreDelayNumber  < minimumFibreDelay){
        NSLog(msg);
        return msg;
    }

    return nil;
}

-(NSString*)validateTellieTriggerDelay:(NSString *)currentText
{
    NSScanner* scanner = [NSScanner scannerWithString:currentText];
    int triggerDelayNumber = [currentText intValue];

    NSString* msg = @"[ELLIE_VALIDATION]: Trigger delay must be a positive integer\n";
    if (![scanner scanInt:nil]){
        NSLog(msg);
        return msg;
    } else if (triggerDelayNumber < 0){
        NSLog(msg);
        return msg;
    }
    return nil;
}

-(NSString*)validateTellieNoPulses:(NSString *)currentText
{
    NSScanner* scanner = [NSScanner scannerWithString:currentText];
    int noPulses = [currentText intValue];

    NSString* msg = @"[ELLIE_VALIDATION]: Number of pulses must be 0 to 5000\n";
    if (![scanner scanInt:nil]){
        NSLog(msg);
        return msg;
    } else if ((noPulses < 0) || (noPulses > 5000)){
        NSLog(msg);
        return msg;
    }
    return nil;
}

// New - November 30, 2022 - Anita Masuskapoe
//
//      Verify that pin delay is 1000-5000 ms
//
-(NSString*)validateTellieSubrunDelay:(NSString *)currentText
{
    NSScanner* scanner = [NSScanner scannerWithString:currentText];
    int subrunDelay = [currentText intValue];

    NSString* msg = @"[ELLIE_VALIDATION]: Subrun delay must be 1000 to 5000ms\n";
    
    if (![scanner scanInt:nil]){
        NSLog(msg);
        return msg;
    } else if ((1000 > subrunDelay)||(subrunDelay > 5000)){
        NSLog(msg);
        return msg;
    }
    return nil;
}

/////////////////////////////////////////////
// Server tab functions
/////////////////////////////////////////////
- (IBAction)telliePing:(id)sender {
    if([model pingTellie]){
        NSString* response = [NSString stringWithFormat:@"Connected to tellie at: %@:%@", [model tellieHost], [model telliePort]];
        [tellieServerResponseTf setStringValue:response];
        [tellieServerResponseTf setBackgroundColor:[NSColor greenColor]];
    } else {
        NSString* response = [NSString stringWithFormat:@"Could not connect to tellie at: %@:%@", [model tellieHost], [model telliePort]];
        [tellieServerResponseTf setStringValue:response];
        [tellieServerResponseTf setBackgroundColor:[NSColor redColor]];
    }
    return;
}

- (IBAction)smelliePing:(id)sender {
    if([model pingSmellie]){
        NSString* response = [NSString stringWithFormat:@"Connected to smellie at: %@:%@", [model smellieHost], [model smelliePort]];
        [smellieServerResponseTf setStringValue:response];
        [smellieServerResponseTf setBackgroundColor:[NSColor greenColor]];
    } else {
        NSString* response = [NSString stringWithFormat:@"Could not connect to smellie at: %@:%@", [model smellieHost], [model smelliePort]];
        [smellieServerResponseTf setStringValue:response];
        [smellieServerResponseTf setBackgroundColor:[NSColor redColor]];
    }
    return;
}

- (IBAction)interlockPing:(id)sender {
    if([model pingInterlock]){
        NSString* response = [NSString stringWithFormat:@"Connected to interlock at: %@:%@", [model interlockHost], [model interlockPort]];
        [interlockServerResponseTf setStringValue:response];
        [interlockServerResponseTf setBackgroundColor:[NSColor greenColor]];
    } else {
        NSString* response = [NSString stringWithFormat:@"Could not connect to interlock at: %@:%@", [model interlockHost], [model interlockPort]];
        [interlockServerResponseTf setStringValue:response];
        [interlockServerResponseTf setBackgroundColor:[NSColor redColor]];
    }
    return;
}

-(void)killInterlock:(NSNotification *)aNote
{
    [model killKeepAlive:aNote];
}

- (IBAction)tubiiRestart:(id)sender {
    //////////////
    //Get a Tubii object
    NSArray*  tubiiModels = [[(ORAppDelegate*)[NSApp delegate] document] collectObjectsOfClass:NSClassFromString(@"TUBiiModel")];
    if(![tubiiModels count]){
        NSLogColor([NSColor redColor], @"[ELLIE]: Couldn't find Tubii model in current experiment.\n");
        return;
    }
    TUBiiModel* theTubiiModel = [tubiiModels objectAtIndex:0];
    if([[theTubiiModel keepAliveThread] isExecuting]){
        NSString* response = @"TUBii keep alive thread is already active.\n";
        [tubiiThreadResponseTf setStringValue:response];
    } else {
        NSString* response = @"TUBii keep alive thread is getting a cold start.\n";
        [tubiiThreadResponseTf setStringValue:response];
        [theTubiiModel activateKeepAlive];
        // Send a ping after a short delay
        [self performSelector:@selector(tubiiPing) withObject:self afterDelay:1];
    }
}

- (void) tubiiPing
{
    //////////////
    //Get a Tubii object
    NSArray*  tubiiModels = [[(ORAppDelegate*)[NSApp delegate] document] collectObjectsOfClass:NSClassFromString(@"TUBiiModel")];
    if(![tubiiModels count]){
        NSLogColor([NSColor redColor], @"[ELLIE]: Couldn't find Tubii model in current experiment.\n");
        return;
    }
    TUBiiModel* theTubiiModel = [tubiiModels objectAtIndex:0];

    // If ping was requested by note, wait to see if keep alive inits OK.
    if([[theTubiiModel keepAliveThread] isExecuting]){
        NSString* response = @"TUBii keep alive thread is active.\n";
        [tubiiThreadResponseTf setStringValue:response];
        [tubiiThreadResponseTf setBackgroundColor:[NSColor greenColor]];
    } else {
        [self tubiiDied:nil];
    }
}

- (IBAction)tubiiPingAction:(id)sender {
    [self tubiiPing];
}

-(void)tubiiDied:(NSNotification*)note{
    NSString* response = @"TUBii keep alive thread is not executing. Please try a restart";
    [tubiiThreadResponseTf setStringValue:response];
    [tubiiThreadResponseTf setBackgroundColor:[NSColor redColor]];
}

@end

