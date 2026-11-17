package main

import (
	"encoding/json"
	"github.com/majd/ipatool/v2/pkg/appstore"
	"net/http"
	"net/url"
	"strings"
	"testing"
)

func TestVaultNeverPersistsPassword(t *testing.T) {
	v := vault{}
	raw, _ := json.Marshal(appstore.Account{Email: "fixture@example.invalid", Password: "fixture-secret", PasswordToken: "fixture-token"})
	if err := v.Set("account", raw); err != nil {
		t.Fatal(err)
	}
	var got appstore.Account
	if err := json.Unmarshal(v["account"], &got); err != nil {
		t.Fatal(err)
	}
	if got.Password != "" || got.PasswordToken != "fixture-token" {
		t.Fatal("password stripping or token retention failed")
	}
}
func TestSignoutClearsAllProvisioning(t *testing.T) {
	out := execute(request{Operation: "signout", State: map[string][]byte{"account": []byte("fixture"), "anisette-v4": []byte("fixture")}})
	if !out.OK || len(out.State) != 0 {
		t.Fatal("signout retained credentials")
	}
}
func TestErrorRedactsPasswordTokenAndEmail(t *testing.T) {
	v := vault{}
	v.Set("account", []byte(`{"passwordToken":"saved-secret-token","email":"fixture@example.invalid"}`))
	got := redactError("bad fixture-password fixture@example.invalid saved-secret-token https://apple.com/path?token=other-secret", request{Password: "fixture-password"}, v)
	for _, secret := range []string{"fixture-password", "fixture@example.invalid", "saved-secret-token", "other-secret"} {
		if strings.Contains(got, secret) {
			t.Fatalf("error contained secret %s", secret)
		}
	}
}
func TestCookiesSurviveKeychainRoundTripAndDeletion(t *testing.T) {
	v := vault{}
	u, _ := url.Parse("https://buy.itunes.apple.com/WebObjects/test")
	jar := newSecureJar(v)
	jar.SetCookies(u, []*http.Cookie{{Name: "session", Value: "cookie-fixture", Path: "/", Secure: true, HttpOnly: true}})
	if err := jar.Save(); err != nil {
		t.Fatal(err)
	}
	restored := newSecureJar(v)
	got := restored.Cookies(u)
	if len(got) != 1 || got[0].Value != "cookie-fixture" {
		t.Fatal("session cookie was not restored")
	}
	restored.SetCookies(u, []*http.Cookie{{Name: "session", MaxAge: -1, Path: "/"}})
	restored.Save()
	if len(newSecureJar(v).Cookies(u)) != 0 {
		t.Fatal("deleted session cookie returned")
	}
}
