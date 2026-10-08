#import "ChatsViewController.h"
#import "ChatViewController.h"
#import "WAAPI.h"
#import "WATheme.h"

@interface ChatsViewController ()
@property (strong, nonatomic) NSArray *chats;
@property (strong, nonatomic) NSTimer *timer;
@end

@implementation ChatsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Chats";
    self.chats = @[];
    self.tableView.rowHeight = 64;
    if (![WATheme flat]) self.tableView.backgroundColor = [UIColor whiteColor];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refresh];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:5 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.timer invalidate];
    self.timer = nil;
}

- (void)refresh {
    [WAAPI getJSON:@"/chats" completion:^(id json, NSError *error) {
        if (error || ![json isKindOfClass:[NSArray class]]) return;
        if ([json isEqual:self.chats]) return;
        self.chats = json;
        [self.tableView reloadData];
    }];
}

+ (NSString *)timeString:(NSTimeInterval)ts {
    if (ts <= 0) return @"";
    static NSDateFormatter *timeFmt, *dateFmt;
    if (!timeFmt) {
        timeFmt = [[NSDateFormatter alloc] init]; timeFmt.dateFormat = @"HH:mm";
        dateFmt = [[NSDateFormatter alloc] init]; dateFmt.dateFormat = @"dd.MM.yy";
    }
    NSDate *d = [NSDate dateWithTimeIntervalSince1970:ts];
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *a = [cal components:NSDayCalendarUnit | NSMonthCalendarUnit | NSYearCalendarUnit fromDate:d];
    NSDateComponents *b = [cal components:NSDayCalendarUnit | NSMonthCalendarUnit | NSYearCalendarUnit fromDate:[NSDate date]];
    BOOL today = a.day == b.day && a.month == b.month && a.year == b.year;
    return today ? [timeFmt stringFromDate:d] : [dateFmt stringFromDate:d];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    return self.chats.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"chat";
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:cid];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
        cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:14];
        cell.detailTextLabel.textColor = [UIColor grayColor];
        UILabel *time = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 60, 20)];
        time.font = [UIFont systemFontOfSize:12];
        time.textColor = [UIColor grayColor];
        time.textAlignment = NSTextAlignmentRight;
        time.backgroundColor = [UIColor clearColor];
        cell.accessoryView = time;
    }
    NSDictionary *c = self.chats[ip.row];
    cell.textLabel.text = c[@"name"];
    cell.detailTextLabel.text = c[@"last"];
    cell.imageView.image = [WATheme avatarForName:c[@"name"]];
    ((UILabel *)cell.accessoryView).text = [ChatsViewController timeString:[c[@"ts"] doubleValue]];
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    NSDictionary *c = self.chats[ip.row];
    ChatViewController *vc = [[ChatViewController alloc] initWithJID:c[@"jid"] name:c[@"name"]];
    [self.navigationController pushViewController:vc animated:YES];
}

@end
