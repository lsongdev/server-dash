#import <Foundation/Foundation.h>
#import "NMSSH.h"

@interface ShellReader : NSObject <NMSSHChannelDelegate>
@property(nonatomic) NSUInteger receivedBytes;
@end
@implementation ShellReader
- (void)channel:(NMSSHChannel *)channel didReadRawData:(NSData *)data {
    @synchronized (self) { self.receivedBytes += data.length; }
}
@end

static void require(BOOL condition, NSString *message) {
    if (!condition) {
        fprintf(stderr, "%s\n", message.UTF8String);
        exit(1);
    }
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        require(argc == 3, @"Usage: maintenance-test PORT CASE");
        NSString *testCase = [NSString stringWithUTF8String:argv[2]];
        NMSSHSession *session = [[NMSSHSession alloc] initWithHost:@"127.0.0.1"
                                                            port:atoi(argv[1])
                                                     andUsername:@"fixture"];
        require([session connectWithTimeout:@2], @"Connection failed");
        require([session authenticateByPassword:@"fixture"], @"Authentication failed");
        session.timeout = @1;
        ShellReader *reader = [ShellReader new];
        session.channel.delegate = reader;
        session.channel.requestPty = YES;
        NSError *error = nil;
        require([session.channel startShell:&error], @"Shell failed");
        [session.channel configureKeepAliveWithInterval:2];

        NSTimeInterval start = NSProcessInfo.processInfo.systemUptime;
        NMSSHConnectionProbeStatus result;
        do {
            NSTimeInterval callStart = NSProcessInfo.processInfo.systemUptime;
            result = [session.channel checkConnection];
            require(NSProcessInfo.processInfo.systemUptime - callStart < 0.5,
                    @"Connection check blocked the caller");
            if (result != NMSSHConnectionProbeStatusPending) { break; }
            [NSThread sleepForTimeInterval:0.05];
        } while (NSProcessInfo.processInfo.systemUptime - start < 1.0);

        if ([testCase isEqualToString:@"unresponsive"]) {
            require(result == NMSSHConnectionProbeStatusPending, @"No-response probe should remain pending");
        } else if ([testCase isEqualToString:@"disconnected"] || [testCase isEqualToString:@"remote-disconnect"]) {
            require(result == NMSSHConnectionProbeStatusFailed, @"Closed transport should fail the probe");
        } else {
            require(result == NMSSHConnectionProbeStatusResponsive, @"Responsive server was rejected");
            require([session.channel sendKeepAlive], @"First keepalive failed");
            [NSThread sleepForTimeInterval:2.2];
            require([session.channel sendKeepAlive], @"Idle keepalive failed");
            // Another check must not reuse a previous probe's successful reply.
            do {
                result = [session.channel checkConnection];
                if (result != NMSSHConnectionProbeStatusPending) { break; }
                [NSThread sleepForTimeInterval:0.05];
            } while (NSProcessInfo.processInfo.systemUptime - start < 4.0);
            if ([testCase isEqualToString:@"resume-unresponsive"]) {
                require(result == NMSSHConnectionProbeStatusPending, @"A stale reply satisfied the new probe");
            } else {
                require(result == NMSSHConnectionProbeStatusResponsive, @"Repeated probe failed");
            }
            @synchronized (reader) {
                require(reader.receivedBytes > 0, @"Shell output stopped during maintenance");
            }
        }
        [session disconnect];
        printf("PASS %s\n", testCase.UTF8String);
    }
    return 0;
}
