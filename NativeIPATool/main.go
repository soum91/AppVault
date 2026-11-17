// AppVault's in-process adapter to pinned MIT-licensed majd/ipatool.
package main

/*
#include <stdlib.h>
*/
import "C"
import (
	"context"
	"encoding/json"
	"errors"
	"github.com/majd/ipatool/v2/pkg/appstore"
	"github.com/majd/ipatool/v2/pkg/util/operatingsystem"
	"github.com/rs/zerolog/log"
	"github.com/schollz/progressbar/v3"
	"io"

	"os"
	"path/filepath"
	"strconv"
	"sync"
	"unsafe"
)

type request struct {
	Operation string
	Email     string
	Password  string
	Code      string
	Term      string
	Directory string
	Identity  string
	App       appstore.App
	State     map[string][]byte
}
type response struct {
	OK    bool              `json:"ok"`
	Error string            `json:"error,omitempty"`
	Code  string            `json:"code,omitempty"`
	Email string            `json:"email,omitempty"`
	Apps  []appstore.App    `json:"apps,omitempty"`
	Path  string            `json:"path,omitempty"`
	State map[string][]byte `json:"state"`
}
type vault map[string][]byte

func (v vault) Get(k string) ([]byte, error) {
	b, ok := v[k]
	if !ok {
		return nil, os.ErrNotExist
	}
	return b, nil
}
func (v vault) Set(k string, b []byte) error {
	if k == "account" {
		var a appstore.Account
		if err := json.Unmarshal(b, &a); err != nil {
			return err
		}
		a.Password = ""
		b, _ = json.Marshal(a)
	}
	v[k] = append([]byte(nil), b...)
	return nil
}
func (v vault) Remove(k string) error { delete(v, k); return nil }

type machine struct{ identity string }

func (m machine) MacAddress() (string, error) { return m.identity, nil }
func (m machine) HomeDirectory() string       { return "" }
func (m machine) ReadPassword(int) ([]byte, error) {
	return nil, errors.New("use AppVault's password field")
}

var mu sync.Mutex
var statusMu sync.Mutex
var phase = "Ready"
var cancel context.CancelFunc
var progress *progressbar.ProgressBar

func setPhase(s string) { statusMu.Lock(); phase = s; statusMu.Unlock() }
func execute(in request) (out response) {
	v := vault(in.State)
	if v == nil {
		v = make(vault)
	}
	out.State = v
	if in.Operation == "signout" {
		for k := range v {
			delete(v, k)
		}
		out.OK = true
		return
	}
	if len(in.Identity) != 17 {
		out.Error = "Missing persistent device identity"
		return
	}
	// Disable upstream global logging. Errors are redacted at the UI boundary.
	log.Logger = log.Output(io.Discard)
	jar := newSecureJar(v)
	defer func() {
		if err := jar.Save(); err != nil {
			out.OK = false
			out.Error = "Could not save cookies"
		}
	}()
	client := appstore.NewAppStore(appstore.Args{Keychain: v, CookieJar: jar, OperatingSystem: operatingsystem.New(), Machine: machine{in.Identity}})
	ctx, stop := context.WithCancel(context.Background())
	defer stop()
	statusMu.Lock()
	cancel = stop
	statusMu.Unlock()
	defer func() { statusMu.Lock(); cancel = nil; progress = nil; phase = "Ready"; statusMu.Unlock() }()
	var err error
	if in.Operation == "login" {
		setPhase("Preparing Apple authentication runtime")
		err = appstore.Prepare(ctx)
		if err == nil {
			setPhase("Signing in with Apple")
			var result appstore.LoginOutput
			result, err = client.Login(appstore.LoginInput{Email: in.Email, Password: in.Password, AuthCode: in.Code})
			out.Email = result.Account.Email
		}
	} else {
		var info appstore.AccountInfoOutput
		info, err = client.AccountInfo()
		if err == nil {
			switch in.Operation {
			case "search":
				setPhase("Searching App Store")
				var r appstore.SearchOutput
				r, err = client.Search(appstore.SearchInput{Account: info.Account, Term: in.Term, Limit: 30, Platform: appstore.PlatformIPhone})
				out.Apps = r.Results
			case "download":
				if err = os.MkdirAll(in.Directory, 0700); err == nil {
					setPhase("Preparing Apple download runtime")
					err = appstore.Prepare(ctx)
					if err == nil {
						p := progressbar.NewOptions64(-1, progressbar.OptionSetWriter(io.Discard))
						statusMu.Lock()
						progress = p
						phase = "Downloading IPA from Apple"
						statusMu.Unlock()
						// Use a numeric filename; catalog names never become paths.
						dest := filepath.Join(in.Directory, fmtID(in.App.ID)+".ipa")
						var result appstore.DownloadOutput
						result, err = client.Download(appstore.DownloadInput{Context: ctx, Account: info.Account, App: in.App, OutputPath: dest, Progress: p, Platform: appstore.PlatformIPhone})
						out.Path = result.DestinationPath
					}
				}
			default:
				err = errors.New("unknown operation")
			}
		}
	}
	if err != nil {
		out.Error = redactError(err.Error(), in, v)
		if errors.Is(err, appstore.ErrAuthCodeRequired) {
			out.Code = "two_factor"
		}
		if errors.Is(err, appstore.ErrLicenseRequired) {
			out.Code = "license_required"
		}
	} else {
		out.OK = true
	}
	return
}

func fmtID(id int64) string { return strconv.FormatInt(id, 10) }

//export AVIPARun
func AVIPARun(input *C.char) *C.char {
	mu.Lock()
	defer mu.Unlock()
	var in request
	var out response
	if err := json.Unmarshal([]byte(C.GoString(input)), &in); err != nil {
		out.Error = "Invalid bridge request"
	} else {
		out = execute(in)
	}
	b, _ := json.Marshal(out)
	return C.CString(string(b))
}

//export AVIPAFree
func AVIPAFree(p *C.char) { C.free(unsafe.Pointer(p)) }

//export AVIPACancel
func AVIPACancel() {
	statusMu.Lock()
	defer statusMu.Unlock()
	if cancel != nil {
		cancel()
	}
}

//export AVIPAStatus
func AVIPAStatus() *C.char {
	statusMu.Lock()
	defer statusMu.Unlock()
	out := map[string]any{"phase": phase}
	if progress != nil {
		s := progress.State()
		out["bytes"] = s.CurrentBytes
		out["total"] = s.Max
	}
	b, _ := json.Marshal(out)
	return C.CString(string(b))
}
func main() {}
