//
//  SiteManager.m
//  Wikish
//
//  Created by YANG ENZO on 12-11-13.
//  Copyright (c) 2012年 Side Trip. All rights reserved.
//

#import "SiteManager.h"
#import "FileUtil.h"
#import "AppUtil.h"
#import "JSONKit.h"
#import "WikiSite.h"
#import "Constants.h"

static NSString *const kSitesFileName = @"sites.json";
static NSString *const kVersionToCompare = @"kVersionToCompare_Sites";

static NSString *const kCommonSitesFileName = @"common-sites.json";
static NSString *const kDefaultSiteKey      = @"default-site";

@interface SiteManager()

@property (nonatomic, retain) NSMutableArray *sites;
@property (nonatomic, retain) NSMutableArray *commonSites;

- (NSString *)_sitesFilePath;
- (NSMutableArray *)_loadSitesFromPlist;
- (NSMutableArray *)_loadSitesFromFile;

- (NSString *)_commonSitesFilePath;
- (NSMutableArray *)_loadCommonSitesFromFile;
- (NSMutableArray *)_defaultCommonSites;

- (WikiSite *)_defaultSite;
- (void)_setDefaultSite:(WikiSite*)site;

- (NSMutableArray *)_loadSitesFromFile:(NSString *)path;

- (NSMutableArray *)_dictsToSites:(NSArray *)dicts;
- (NSMutableArray *)_sitesToDicts:(NSArray *)sites;
- (void)_mergeSites;
- (BOOL)_justUpdatedToNewVersion;
- (void)_saveSites;
- (void)_saveCommonSites;

@end

@implementation SiteManager

@synthesize sites = _sites;
@synthesize commonSites = _commonSites;

+ (SiteManager *)sharedInstance {
    static SiteManager *sharedInstance = nil;
    @synchronized(self) {
        if (sharedInstance == nil) sharedInstance = [self new];
    }
    return sharedInstance;
}

- (id)init {
    self = [super init];
    if (self) {
        self.sites = [self _loadSitesFromFile];
        if (nil == _sites) {
            self.sites = [self _loadSitesFromPlist];
        } else if ([self _justUpdatedToNewVersion]) {
            [self _mergeSites];
        }
    }
    return self;
}

- (void)dealloc {
    self.sites = nil;
    self.commonSites = nil;
    [super dealloc];
}

- (NSArray *)supportedSites {
    return _sites;
}

- (NSArray *)commonSites {
    if (_commonSites) {
        if ([_commonSites count] == 0) {
            [_commonSites addObject:[self defaultSite]];
            [self _saveCommonSites];
        }
        return _commonSites;
    }
    
    // from file
    NSMutableArray *sites = [self _loadCommonSitesFromFile];
    if (sites) {
        self.commonSites = sites;
        return _commonSites;
    }
    // generate
    self.commonSites = [self _defaultCommonSites];
    [self _saveCommonSites];
    return _commonSites;
}

- (WikiSite *)defaultSite {
    WikiSite *site = [self _defaultSite];
    if (site) return site;
    
    NSString *lang = [[NSLocale preferredLanguages] objectAtIndex:0];
    site = [self siteOfLang:lang];
    if (site == nil) {
        site = [[WikiSite alloc] initWithName:lang lang:lang sublang:@"wiki"];
    }
    
    [self _setDefaultSite:site];
    
    return site;
}

- (WikiSite *)_defaultSite {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSData *data = [defaults objectForKey:kDefaultSiteKey];
    if (!data) return nil;
    WikiSite *site = (WikiSite *)[NSKeyedUnarchiver unarchiveObjectWithData:data];
    return site;
}

- (void)_setDefaultSite:(WikiSite *)site {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:site];
    [defaults setObject:data forKey:kDefaultSiteKey];
    [defaults synchronize];
}

- (WikiSite *)alterDefaultSite {
    NSArray *commonSites = [self commonSites];
    WikiSite *curSite = [self defaultSite];
    WikiSite *theSite = nil;
    for (WikiSite *aSite in commonSites) {
        if ([aSite sameAs:curSite]) {
            theSite = aSite;
            break;
        }
    }
    
    if (!theSite) {
        theSite = [commonSites objectAtIndex:0];
        [self setDefaultSite:theSite];
    } else {
        NSInteger index = [commonSites indexOfObject:theSite];
        index = (index + 1) % [commonSites count];
        theSite = [commonSites objectAtIndex:index];
        [self setDefaultSite:theSite];
    }
    // TODO(enzo) notify
    return theSite;
}

- (void)setDefaultSite:(WikiSite *)site {
    [self _setDefaultSite:site];
}

- (void)addCommonSite:(WikiSite *)site {
    if ([self isCommonSite:site]) return;
    [_commonSites addObject:site];
    [self _saveCommonSites];
}

- (BOOL)isCommonSite:(WikiSite *)site {
    NSArray *arr = [self commonSites];
    for (WikiSite *aSite in arr) {
        if ([aSite sameAs:site]) {
            return YES;
        }
    }
    return NO;
}

- (void)removeCommonSite:(WikiSite *)site {
    if (!_commonSites) return;
    if ([self isCommonSite:site]) {
        // TODO(enzo) notify
        return;
    }
    for (WikiSite *aSite in _commonSites) {
        if ([aSite sameAs:site]) {
            [_commonSites removeObject:aSite];
            return;
        }
    }
}

- (void)addSite:(WikiSite *)site {
    if ([self hasSite:site]) {
        // TODO(enzo) Notify
        return;
    }
    [_sites addObject:site];
    [self _saveSites];
}

- (BOOL)hasSite:(WikiSite *)site {
    for (WikiSite *aSite in _sites) {
        if ([aSite sameAs:site]) return YES;
    }
    return NO;
}

- (void)removeSite:(WikiSite *)site {
    for (WikiSite *aSite in _sites) {
        if ([aSite sameAs:site]) {
            [_sites removeObject:aSite];
            return;
        }
    }
}

- (WikiSite *)siteOfLang:(NSString *)lang {
    lang = [lang lowercaseString];
    for (WikiSite *site in _sites) {
        if ([site.lang isEqualToString:lang] || [site.sublang isEqualToString:lang])
            return site;
    }
    return nil;
}

- (WikiSite *)siteOfName:(NSString *)name {
    for (WikiSite *site in _sites) {
        if ([site.name isEqualToString:name])
            return site;
    }
    return nil;
}

- (NSString *)_sitesFilePath {
    return [[FileUtil documentPath] stringByAppendingPathComponent:kSitesFileName];
}

- (NSMutableArray *)_loadSitesFromPlist {
    NSString *plistPath = [[NSBundle mainBundle] pathForResource:@"Sites" ofType:@"plist"];
    NSArray *dicts = [NSArray arrayWithContentsOfFile:plistPath];
    return [self _dictsToSites:dicts];
}

- (NSMutableArray *)_loadSitesFromFile {
    NSString *path = [self _sitesFilePath];
    return [self _loadSitesFromFile:path];
}

- (NSString *)_commonSitesFilePath {
    return [[FileUtil documentPath] stringByAppendingPathComponent:kCommonSitesFileName];
}

- (NSMutableArray *)_loadCommonSitesFromFile {
    NSString *path = [self _commonSitesFilePath];
    return [self _loadSitesFromFile:path];
}

- (NSMutableArray *)_loadSitesFromFile:(NSString *)path {
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;
    
    NSData *siteData = [NSData dataWithContentsOfFile:path];
    NSArray *arr = [siteData objectFromJSONData];
    if ([arr isKindOfClass:[NSArray class]]) {
        return [self _dictsToSites:arr];
    }
    return nil;
}

- (NSMutableArray *)_defaultCommonSites {
    WikiSite *defaultSite = [self defaultSite];
    WikiSite *site = nil;
    if (![defaultSite.lang isEqualToString:@"en"]) site = [self siteOfLang:@"en"];
    
    NSMutableArray *commonSites = [NSMutableArray arrayWithObjects:defaultSite, site, nil];
    
    return commonSites;
}

- (NSMutableArray *)_dictsToSites:(NSArray *)dicts {
    if (!dicts) return nil;
    NSMutableArray *sites = [[NSMutableArray new] autorelease];
    for (NSDictionary *dict in dicts) {
        WikiSite *site = [[WikiSite alloc] initWithDictionary:dict];
        if (site) [sites addObject:site];
        [site release];
    }
    return sites;
}

- (NSMutableArray *)_sitesToDicts:(NSArray *)sites {
    if (!sites) return nil;
    NSMutableArray *dicts = [[NSMutableArray new] autorelease];
    for (WikiSite *site in sites) {
        NSDictionary *dict = [site toDictionary];
        [dicts addObject:dict];
    }
    return dicts;
}

- (void)_mergeSites {
    NSArray *plistSites = [self _loadSitesFromPlist];
    NSMutableArray *appends = [NSMutableArray new];
    
    for (WikiSite *plistSite in plistSites) {
        BOOL exist = NO;
        for (WikiSite *site in _sites) {
            if ([site sameAs:plistSite]) {
                [site copy:plistSite];
                exist = YES;
                break;
            }
        }
        
        if (!exist) {
            [appends addObject:plistSite];
        }
    }
    
    [_sites addObjectsFromArray:appends];
    [appends release];
    
    [self _saveSites];
}

- (BOOL)_justUpdatedToNewVersion {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSString *currentVersion = [AppUtil currentVersion];
    
    NSString *recordedVersion = [userDefaults valueForKey:kVersionToCompare];
    
    if ([currentVersion isEqualToString:recordedVersion]) {
        return NO;
    } else {
        [userDefaults setValue:currentVersion forKey:kVersionToCompare];
        [userDefaults synchronize];
    }
    return YES;
}

- (void)_saveSites {
    NSArray *dicts = [self _sitesToDicts:_sites];
    NSData *data = [dicts JSONData];
    [data writeToFile:[self _sitesFilePath] atomically:YES];
}

- (void)_saveCommonSites {
    if (_commonSites == nil) {
        return;
    }
    
    NSArray *dicts = [self _sitesToDicts:_commonSites];
    NSData *data = [dicts JSONData];
    [data writeToFile:[self _commonSitesFilePath] atomically:YES];
}

@end