package main

import (
	"encoding/json"
	"net/http"
	"net/http/cookiejar"
	"net/url"
	"sync"
)

type savedCookie struct {
	URL    string
	Cookie *http.Cookie
}
type secureJar struct {
	*cookiejar.Jar
	mu      sync.Mutex
	entries map[string]savedCookie
	vault   vault
}

func newSecureJar(v vault) *secureJar {
	base, _ := cookiejar.New(nil)
	j := &secureJar{Jar: base, entries: map[string]savedCookie{}, vault: v}
	if data, err := v.Get("appvault-cookies"); err == nil {
		var entries map[string]savedCookie
		if json.Unmarshal(data, &entries) == nil {
			for k, e := range entries {
				if u, err := url.Parse(e.URL); err == nil && e.Cookie != nil {
					base.SetCookies(u, []*http.Cookie{e.Cookie})
					j.entries[k] = e
				}
			}
		}
	}
	return j
}
func (j *secureJar) SetCookies(u *url.URL, cookies []*http.Cookie) {
	j.mu.Lock()
	defer j.mu.Unlock()
	j.Jar.SetCookies(u, cookies)
	for _, c := range cookies {
		domain := c.Domain
		if domain == "" {
			domain = u.Hostname()
		}
		path := c.Path
		if path == "" {
			path = u.EscapedPath()
		}
		key := domain + "\n" + path + "\n" + c.Name
		if c.MaxAge < 0 {
			delete(j.entries, key)
		} else {
			copy := *c
			j.entries[key] = savedCookie{u.String(), &copy}
		}
	}
}
func (j *secureJar) Save() error {
	j.mu.Lock()
	defer j.mu.Unlock()
	b, err := json.Marshal(j.entries)
	if err != nil {
		return err
	}
	return j.vault.Set("appvault-cookies", b)
}
