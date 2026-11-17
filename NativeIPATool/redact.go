package main

import (
	"encoding/json"
	"regexp"
	"strings"
)

var credentialFields = regexp.MustCompile(`(?i)(password|passwordToken|token|authorization|cookie|dsid|directoryServicesIdentifier|email)(["'\s:=]+)[^\s,;<>]+`)
var queryValues = regexp.MustCompile(`(https?://[^\s?]+)\?[^\s]+`)

// Account values are removed before any error leaves Go. Neither raw requests
// nor raw response bodies are added to a diagnostic report.
func redactError(message string, in request, v vault) string {
	secrets := []string{in.Password, in.Email, in.Code}
	if raw, ok := v["account"]; ok {
		var account map[string]any
		if json.Unmarshal(raw, &account) == nil {
			for _, k := range []string{"password", "passwordToken", "directoryServicesIdentifier", "email"} {
				if s, ok := account[k].(string); ok {
					secrets = append(secrets, s)
				}
			}
		}
	}
	if raw, ok := v["appvault-cookies"]; ok {
		var cookies map[string]savedCookie
		if json.Unmarshal(raw, &cookies) == nil {
			for _, c := range cookies {
				if c.Cookie != nil {
					secrets = append(secrets, c.Cookie.Value)
				}
			}
		}
	}
	for _, s := range secrets {
		if s != "" {
			message = strings.ReplaceAll(message, s, "[redacted]")
		}
	}
	message = queryValues.ReplaceAllString(message, "$1?[redacted]")
	message = credentialFields.ReplaceAllString(message, "$1=[redacted]")
	if len(message) > 1500 {
		message = message[:1500] + "…"
	}
	return message
}
