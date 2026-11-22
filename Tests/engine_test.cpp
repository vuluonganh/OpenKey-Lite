// Engine regression tests: types key sequences into the OpenKey engine and
// replays its output the same way macOS/ModernKey/OpenKey.mm does
// (backspaces, then the new characters, then the typed key on restore).
//
// Run with Tests/run.sh. `--golden` prints every (config, input) result so the
// output can be diffed against Tests/golden.txt after engine changes.

#include <cstdio>
#include <cstring>
#include <string>
#include <vector>
#include <unistd.h>
#include <sys/wait.h>

#include "Engine.h"

// Settings normally defined by the app (macOS/ModernKey/AppDelegate.m).
int vLanguage = 1;
int vSwitchKeyStatus = 0;
int vUseModernOrthography = 1;
int vRestoreIfWrongSpelling = 0;

struct Config {
    const char* name;
    int modern, restoreWrong;
};

static const Config kConfigs[] = {
    {"default",       1, 0},
    {"old-marks",     0, 0},
    {"restore-wrong", 1, 1},
};

static void apply(const Config& c) {
    vUseModernOrthography = c.modern;
    vRestoreIfWrongSpelling = c.restoreWrong;
}

static void appendUtf8(std::string& out, Uint32 cp) {
    if (cp < 0x80) out += (char)cp;
    else if (cp < 0x800) { out += (char)(0xC0 | (cp >> 6)); out += (char)(0x80 | (cp & 0x3F)); }
    else { out += (char)(0xE0 | (cp >> 12)); out += (char)(0x80 | ((cp >> 6) & 0x3F)); out += (char)(0x80 | (cp & 0x3F)); }
}

// '\b' = backspace, '\n' = return; everything else maps through _characterMap.
static std::string type(const std::string& input) {
    vKeyHookState* hook = (vKeyHookState*)vKeyInit();
    std::vector<Uint32> screen;

    for (unsigned char ch : input) {
        Uint16 key;
        bool caps = false;
        if (ch == '\b') key = KEY_DELETE;
        else if (ch == '\n') key = KEY_RETURN;
        else {
            auto it = _characterMap.find(ch);
            if (it == _characterMap.end()) { fprintf(stderr, "unmapped char %c\n", ch); exit(2); }
            key = (Uint16)(it->second & CHAR_MASK);
            caps = (it->second & CAPS_MASK) != 0;
        }
        vKeyHandleEvent(vKeyEvent::Keyboard, vKeyEventState::KeyDown, key, caps ? 1 : 0, false);

        if (hook->code == vDoNothing) { // key passes through untouched
            if (key == KEY_DELETE) { if (!screen.empty()) screen.pop_back(); }
            else screen.push_back(key == KEY_RETURN ? '\n' : ch);
            continue;
        }

        if (hook->backspaceCount > 0 && hook->backspaceCount < MAX_BUFF)
            for (int i = 0; i < hook->backspaceCount && !screen.empty(); i++) screen.pop_back();
        for (int k = hook->newCharCount - 1; k >= 0; k--) {
            Uint32 c = hook->charData[k];
            if (c & PURE_CHARACTER_MASK) screen.push_back((Uint16)c);
            else if (!(c & CHAR_CODE_MASK)) screen.push_back(keyCodeToCharacter(c));
            else screen.push_back((Uint16)c);
        }
        if (hook->code == vRestore || hook->code == vRestoreAndStartNewSession) {
            Uint16 typed = keyCodeToCharacter(key | (caps ? CAPS_MASK : 0));
            screen.push_back(typed ? typed : (key == KEY_RETURN ? '\n' : '?'));
        }
        if (hook->code == vRestoreAndStartNewSession) startNewSession();
    }

    std::string out;
    for (Uint32 cp : screen) appendUtf8(out, cp);
    return out;
}

// Each case runs in a fresh process so engine globals never leak between cases.
static std::string typeIsolated(const Config& c, const std::string& input) {
    int fd[2];
    if (pipe(fd) != 0) { perror("pipe"); exit(2); }
    pid_t pid = fork();
    if (pid == 0) {
        close(fd[0]);
        apply(c);
        std::string r = type(input);
        write(fd[1], r.data(), r.size());
        _exit(0);
    }
    close(fd[1]);
    std::string r;
    char buf[512];
    ssize_t n;
    while ((n = read(fd[0], buf, sizeof buf)) > 0) r.append(buf, n);
    close(fd[0]);
    int status = 0;
    waitpid(pid, &status, 0);
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) return "<crash>";
    return r;
}

struct Case { const char* config; const char* input; const char* expected; };

// Hand-checked Telex expectations.
static const Case kCases[] = {
    {"default", "tieengs vieetj", "tiếng việt"},
    {"default", "nguowif", "người"},
    {"default", "dduwowngf", "đường"},
    {"default", "quaas", "quấ"},
    {"default", "gif", "gì"},
    {"default", "hoaf", "hoà"},
    {"default", "thuyr", "thuỷ"},
    {"default", "khoer", "khoẻ"},
    {"default", "Vieetj Nam", "Việt Nam"},
    {"default", "VIEETJ", "VIỆT"},
    {"default", "w", "ư"},
    {"default", "ww", "w"},
    {"default", "[", "ơ"},
    {"default", "]", "ư"},
    {"default", "tuwj", "tự"},
    {"default", "aas", "ấ"},
    {"default", "ass", "as"},
    {"default", "aaa", "aa"},
    {"default", "ddd", "dd"},
    {"default", "tieengs\b", "tiến"},
    {"default", "mootj hai ba", "một hai ba"},
    {"default", "xin chaof", "xin chào"},
    {"default", "hoaf\bf", "hò"},
    {"default", "tiengs", "tiéng"},
    {"default", "tieengsz", "tiêng"},
    {"old-marks", "hoaf", "hòa"},
    {"old-marks", "thuyr", "thủy"},
    {"old-marks", "khoer", "khỏe"},
    {"restore-wrong", "windows ", "windows "},
};

// Inputs replayed under every config for the golden file.
static const char* kCorpus[] = {
    "tieengs vieetj", "nguowif", "dduwowngf", "quaas", "gif", "giaf", "gieets", "hoaf", "hoar", "hoas",
    "thuyr", "thuys", "khoer", "khuyeens", "khuyur", "Vieetj Nam", "VIEETJ NAM", "w", "ww", "www", "[", "]",
    "[[", "]]", "tuwj", "aas", "ass", "aaa", "ddd", "dd", "DD", "Dd", "tieengs\b", "tieengs\b\b\b",
    "mootj hai ba", "xin chaof", "hoaf\bf", "tiengs", "tieengz", "thuowr", "thuow", "thuowng", "huowu",
    "khuyar", "ngoafi", "oaf", "uyeenr", "chuyeenj", "nghieeng", "quoocs", "quyeets", "gioongs", "giuwax",
    "muoons", "muoonsn", "dduwocj", "uow", "uwow", "uwowc", "muwowif", "trowf", "chaof banj", "ddeens",
    "tooi ddi hocj", "baif hats", "windows", "windows ", "google", "facebook", "class", "string", "export",
    "lambda", "test", "tesst", "foo bar", "hello world", "zoom", "fanh", "jang", "wen", "hag", "vih", "bak",
    "cc", "gg", "kk", "nn", "qq", "pp", "tt", "uu", "xin chaof. ban", "xin chaof\nban", "a. b. c",
    "Tieengs Vieetj", "tIEENGS", "TiEeNgS", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "thisisaverylongwordthatexceedsthirtytwocharactersforsure", "nguowif nguowif nguowif",
    "1234", "abc123", "a1", "hello, world.", "\"quoted\"", "it's", "x-y", "(test)", "a;b", "a/b",
    "ddi\b\bddi", "vieetj \bj", "hoaf \b\bf", "toi\b\b\boois", "sao ddaau", "ca phee", "phowr", "bunf chaar",
    "nhaf", "nhaaf", "nhaaaf", "ruouwj", "ruowuj", "ruwowuj", "khoong", "kho6ng", "thoong", "thooong",
    "loaij", "loajij", "quanr lys", "quaanf aos", "Quaanf Aos", "QUAANF AOS", "fw", "fww", "jw",
};

int main(int argc, char** argv) {
    if (argc > 1 && strcmp(argv[1], "--golden") == 0) {
        for (const Config& c : kConfigs)
            for (const char* in : kCorpus) {
                std::string shown = in;
                for (char& ch : shown) { if (ch == '\b') ch = '<'; else if (ch == '\n') ch = '|'; }
                std::string out = typeIsolated(c, in);
                for (char& ch : out) if (ch == '\n') ch = '|';
                printf("%-13s %-45s => %s\n", c.name, shown.c_str(), out.c_str());
            }
        return 0;
    }

    int failed = 0, total = 0;
    for (const Case& t : kCases) {
        const Config* cfg = nullptr;
        for (const Config& c : kConfigs) if (strcmp(c.name, t.config) == 0) cfg = &c;
        std::string got = typeIsolated(*cfg, t.input);
        total++;
        if (got != t.expected) {
            failed++;
            std::string shown = t.input;
            for (char& ch : shown) if (ch == '\b') ch = '<';
            printf("FAIL [%s] \"%s\": expected \"%s\", got \"%s\"\n", t.config, shown.c_str(), t.expected, got.c_str());
        }
    }
    printf("%d/%d passed\n", total - failed, total);
    return failed ? 1 : 0;
}
