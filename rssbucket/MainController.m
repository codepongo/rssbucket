//
//  MainController.m
//  rssbucket
//
// Copyright 2008 Brian Dunagan (brian@bdunagan.com)
//
// MIT License
// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use,
// copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following
// conditions:
//
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
// OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
// HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
// WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
// OTHER DEALINGS IN THE SOFTWARE.
//

#import "MainController.h"
#import "Feed.h"
#import "FeedItem.h"
#import "BDLinkArrowCell.h"

// Update every 10 minutes.
static int UPDATE_FEED_INTERVAL = 600;
#define DEFAULTS_KEY @"feeds"

@implementation MainController

@synthesize shouldChange = _shouldChange;

- (id) init
{
	self = [super init];
	if (self != nil)
	{
		_isUpdatingFeeds = NO;
		
		// Trigger update timer periodically.
		[NSTimer scheduledTimerWithTimeInterval:UPDATE_FEED_INTERVAL
										 target:self
									   selector:@selector(updateFeeds:)
									   userInfo:nil
										repeats:YES];
	}
	return self;
}

- (void)awakeFromNib
{
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
		//[feeds setSelectionIndex:0];
	// Check user defaults.
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSArray* ar = [defaults objectForKey:DEFAULTS_KEY];
	 
	_shouldChange = NO;
	for (id data in ar)
	{
		Feed *feed = [NSKeyedUnarchiver unarchiveObjectWithData:data];
		[feeds addObject:feed];
		[sourceList reloadData];
	}
	[feeds setSelectedObjects:nil];
	_shouldChange = YES;
	// Disable remove buttons if no feeds.
	[self setRemoveFeed:[[feeds arrangedObjects] count] > 0];




}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
	// Update user defaults.
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSMutableArray* ar = [NSMutableArray array];
	
	NSEnumerator *feedEnumerator = [[feeds arrangedObjects] objectEnumerator];
	Feed *feed;
	while (feed = [feedEnumerator nextObject])
	{
		NSData* data = [NSKeyedArchiver archivedDataWithRootObject:feed];
		[ar addObject:data];
	}
	
	[defaults setObject:ar forKey:DEFAULTS_KEY];
	
	return NSTerminateNow;
}

//
// Properties
//

- (NSArrayController *)feeds
{
	return feeds;
}

//
// UI Methods
//

- (IBAction)clickAddRemoveButtons:(id)sender
{
	int segmentIndex = [sender selectedSegment];
	[sender setSelected:NO forSegment:segmentIndex];
	if (segmentIndex == 0)
	{
		// Add
		[self clickAddFeed:nil];
	}
	else
	{
		// Remove
		[self clickRemoveFeed:nil];
	}
}

- (IBAction)clickAddFeed:(id)sender
{
	// Null out any lingering data.
	[validateIcon setImage:nil];
	[urlField setStringValue:@""];

	[NSApp beginSheet:addFeedSheet
	   modalForWindow:[NSApp mainWindow]
		modalDelegate:nil
	   didEndSelector:nil
		  contextInfo:nil];
}

- (IBAction)clickRemoveFeed:(id)sender
{
	NSArray* selectedObjects = [feeds selectedObjects];
	if ([selectedObjects count] == 0)
	{
		return;
	}
	[feeds removeObjects:selectedObjects];

	// Reload source list.
	[sourceList reloadData];
	return;
	if ([sourceList selectedRow] < 0)
	{
		[sourceList selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
	}

	// Disable remove buttons if no feeds.
	if ([[feeds arrangedObjects] count] == 0)
	{
		[self setRemoveFeed:NO];
	}
}

- (IBAction)clickExportRss:(id)sender
{
	NSSavePanel *save = [NSSavePanel savePanel];
	[save runModal];
	NSURL* file = [save URL];
	NSMutableArray* feedString = [NSMutableArray array];
	NSEnumerator* e = [[feeds arrangedObjects] objectEnumerator];
	Feed* feed;
	while (feed = [e nextObject])
	{
		[feedString addObject:[[feed valueForKeyPath:@"properties.url"] absoluteString]];
	}
	[feedString writeToURL:file atomically:YES];
}

- (IBAction)okAddFeed:(id)sender
{
	NSString *feedString = [urlField stringValue];
	BOOL isAdded = [self addFeedToList:feedString];
	if (isAdded)
	{
		[NSApp endSheet:addFeedSheet];
		[addFeedSheet orderOut:self];
		[sourceList selectRowIndexes:[NSIndexSet indexSetWithIndex:[feeds selectionIndex]] byExtendingSelection:NO];

		// Enable remove buttons just in case.
		[self setRemoveFeed:YES];
	}
	else
	{
		[validateIcon setImage:[NSImage imageNamed:NSImageNameInvalidDataFreestandingTemplate]];
	}
}

- (IBAction)cancelAddFeed:(id)sender	
{
	[NSApp endSheet:addFeedSheet];
    [addFeedSheet orderOut:self];
}

- (IBAction)openURLInBrowser:(id)sender
{
	if ([[feedItems selectedObjects] count] > 0)
	{
		// Load selected item into WebView.
		FeedItem *selectedItem = [[feedItems selectedObjects] objectAtIndex:0];
		NSURL *url = [[[selectedItem properties] objectForKey:@"url"] copy];
		[[NSWorkspace sharedWorkspace] openURL:url];
	}
}

- (IBAction)updateFeeds:(id)sender
{
	// Ensure the update thread is a singleton.
	if (_updateThread == nil || [_updateThread isFinished])
	{
		[_updateThread release];
		_updateThread = [[NSThread alloc] initWithTarget:self selector:@selector(_updateFeeds) object:nil];
		[_updateThread start];
	}
}

//
// Methods
//

- (void)_updateFeeds
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	[self setRemoveFeed:NO];

	NSLog(@"updating feeds");
	NSArray *feedArray = [feeds arrangedObjects];
	NSEnumerator *feedEnumerator = [feedArray objectEnumerator];
	Feed *feed;
	while (feed = [feedEnumerator nextObject])
	{
		[sourceList setNeedsDisplay:YES];
		[feed updateFeed];
		[sourceList setNeedsDisplay:YES];
	}
	
	[self setRemoveFeed:YES];
	
	[pool release];
}

- (BOOL)addFeedToList:(NSString *)feedString
{
	NSString* urlStr;
	if ([feedString hasPrefix:@"feed://"])	{
		NSRange r = NSMakeRange(7, [feedString length] - 7);
		urlStr = [@"http://" stringByAppendingString:[feedString substringWithRange:r]];
	}
	else {
		urlStr = feedString;
	}
	
	
	{	
		NSEnumerator *feedEnumerator = [[feeds arrangedObjects] objectEnumerator];

		Feed *feed;
		while (feed = [feedEnumerator nextObject])
		{
			if ([urlStr isEqualToString:[[feed valueForKeyPath:@"properties.url"] absoluteString]])
			{
				_shouldChange = NO;
				[feeds setSelectedObjects:[NSArray arrayWithObject:feed]];
				_shouldChange = YES;
				return YES;
			}
		}
	}
	
	NSURL *feedUrl = [NSURL URLWithString:urlStr];
	Feed* feed = [[[Feed alloc] initWithUrl:feedUrl] autorelease];
	if (feed != nil)
	{
		_shouldChange = NO;
		[feeds addObject:feed];
		_shouldChange = YES;
		[sourceList reloadData];
		return YES;
	}
	else
	{
		return NO;
	}
}

- (void)loadUrlIntoWebView:(NSURL *)url
{
	[[webView mainFrame] loadRequest:[NSURLRequest requestWithURL:url]];
}

- (void)updateWebView
{
	if ([[feedItems selectedObjects] count] > 0)
	{
		// Load selected item into WebView.
		FeedItem *selectedItem = [[feedItems selectedObjects] objectAtIndex:0];
		NSURL *url = [[selectedItem properties] objectForKey:@"url"];
		//[self loadUrlIntoWebView:url];
		NSString* description = [[selectedItem properties] objectForKey:@"description"];
		[[webView mainFrame] loadHTMLString: description baseURL:url];
		selectedItem.unRead = NO;
		
	}
}

- (void)setRemoveFeed:(BOOL)isEnabled
{
	[addRemoveButtons setEnabled:isEnabled forSegment:1];
	[removeMenuItem setEnabled:isEnabled];
}

//
// TableView delegates
//

- (void)tableView:(NSTableView *)aTableView willDisplayCell:(id)aCell forTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
	if ([[aTableColumn identifier] isEqualToString:@"Title"])
	{
		// Set title.
		FeedItem *currentFeedItem = [[feedItems arrangedObjects] objectAtIndex:rowIndex];
		[aCell setTitle:[currentFeedItem valueForKeyPath:@"properties.title"]];
		
		// Set link arrow visibility.
		[aCell setLinkVisible:([aTableView selectedRow] == rowIndex)];
	}
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
	if (_shouldChange)
	{
		[self updateWebView];
	}
	[sourceList setNeedsDisplay:YES];
	[itemsView deselectAll:self];
}

//
// SplitView delegates
//

- (CGFloat)splitView:(NSSplitView *)sender constrainMaxCoordinate:(CGFloat)proposedMax ofSubviewAt:(NSInteger)offset
{
	if (sender == sourceListSplitView && offset == 0)
	{
		return 300;
	}
	else
	{
		return proposedMax;
	}
}

- (CGFloat)splitView:(NSSplitView *)sender constrainMinCoordinate:(CGFloat)proposedMin ofSubviewAt:(NSInteger)offset
{
	if (sender == sourceListSplitView && offset == 0)
	{
		return 150;
	}
	else if (sender == itemsSplitView && offset == 0)
	{
		return 100;
	}
	else
	{
		return proposedMin;
	}
}

@end
