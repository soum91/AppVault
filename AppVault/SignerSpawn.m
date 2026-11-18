#import <Foundation/Foundation.h>
#include <spawn.h>
#include <signal.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/wait.h>

extern char **environ;

/// Starts the rootless signer helper with stdin/stdout pipes. Returns the pid,
/// or -errno on failure. stderr goes to /dev/null.
pid_t AVSpawnSigner(NSString *path, NSArray<NSString *> *arguments, int *writeFD, int *readFD) {
    int input[2], output[2];
    if (pipe(input) != 0) return -errno;
    if (pipe(output) != 0) { int e = errno; close(input[0]); close(input[1]); return -e; }
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, input[0], STDIN_FILENO);
    posix_spawn_file_actions_adddup2(&actions, output[1], STDOUT_FILENO);
    posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0);
    posix_spawn_file_actions_addclose(&actions, input[1]);
    posix_spawn_file_actions_addclose(&actions, output[0]);

    NSUInteger count = arguments.count + 1;
    char **argv = calloc(count + 1, sizeof(char *));
    argv[0] = strdup(path.fileSystemRepresentation);
    for (NSUInteger i = 0; i < arguments.count; i++) argv[i + 1] = strdup(arguments[i].UTF8String);
    pid_t pid = 0;
    int status = posix_spawn(&pid, argv[0], &actions, NULL, argv, environ);
    for (NSUInteger i = 0; i < count; i++) free(argv[i]);
    free(argv);
    posix_spawn_file_actions_destroy(&actions);
    close(input[0]); close(output[1]);
    if (status != 0) { close(input[1]); close(output[0]); return -status; }
    fcntl(input[1], F_SETFD, FD_CLOEXEC);
    fcntl(output[0], F_SETFD, FD_CLOEXEC);
    *writeFD = input[1];
    *readFD = output[0];
    return pid;
}

void AVStopSigner(pid_t pid) {
    if (pid <= 0) return;
    kill(pid, SIGKILL);
    int status = 0;
    waitpid(pid, &status, 0);
}
