package controller

import (
	"encoding/json"
	"strings"
	"testing"

	appsv1alpha1 "github.com/openclaw/openclaw-operator/operator/api/v1alpha1"
)

func TestValidateNodeSpec(t *testing.T) {
	t.Run("requires runtime secret", func(t *testing.T) {
		err := validateNodeSpec(&appsv1alpha1.OpenClawNode{})
		if err == nil {
			t.Fatal("expected validation error for missing runtime secret")
		}
	})

	t.Run("requires ingress host when enabled", func(t *testing.T) {
		node := &appsv1alpha1.OpenClawNode{}
		node.Spec.RuntimeSecretRef.Name = "runtime"
		node.Spec.Ingress = &appsv1alpha1.OpenClawIngressSpec{Enabled: true}

		err := validateNodeSpec(node)
		if err == nil {
			t.Fatal("expected validation error for ingress without host")
		}
	})

	t.Run("rejects invalid config mode", func(t *testing.T) {
		node := &appsv1alpha1.OpenClawNode{}
		node.Spec.RuntimeSecretRef.Name = "runtime"
		node.Spec.ConfigMode = "invalid"

		err := validateNodeSpec(node)
		if err == nil {
			t.Fatal("expected validation error for invalid config mode")
		}
	})

	t.Run("accepts valid spec", func(t *testing.T) {
		node := &appsv1alpha1.OpenClawNode{}
		node.Spec.RuntimeSecretRef.Name = "runtime"
		node.Spec.ConfigMode = "merge"
		node.Spec.Ingress = &appsv1alpha1.OpenClawIngressSpec{
			Enabled: true,
			Host:    "node-a.example.com",
		}

		if err := validateNodeSpec(node); err != nil {
			t.Fatalf("expected valid spec, got error: %v", err)
		}
	})
}

func TestURLForNode(t *testing.T) {
	t.Run("uses service URL by default", func(t *testing.T) {
		node := &appsv1alpha1.OpenClawNode{}
		node.Name = "node-a"
		node.Namespace = "openclaw"

		got := urlForNode(node)
		want := "http://node-a.openclaw.svc:18789"
		if got != want {
			t.Fatalf("unexpected URL: got %q want %q", got, want)
		}
	})

	t.Run("uses http ingress URL without tls", func(t *testing.T) {
		node := &appsv1alpha1.OpenClawNode{}
		node.Spec.Ingress = &appsv1alpha1.OpenClawIngressSpec{
			Enabled: true,
			Host:    "node-a.example.com",
		}

		got := urlForNode(node)
		want := "http://node-a.example.com"
		if got != want {
			t.Fatalf("unexpected URL: got %q want %q", got, want)
		}
	})

	t.Run("uses https ingress URL with tls", func(t *testing.T) {
		node := &appsv1alpha1.OpenClawNode{}
		node.Spec.Ingress = &appsv1alpha1.OpenClawIngressSpec{
			Enabled:       true,
			Host:          "node-a.example.com",
			TLSSecretName: "node-a-tls",
		}

		got := urlForNode(node)
		want := "https://node-a.example.com"
		if got != want {
			t.Fatalf("unexpected URL: got %q want %q", got, want)
		}
	})
}

func TestRenderOpenClawConfig(t *testing.T) {
	node := &appsv1alpha1.OpenClawNode{}
	node.Name = "node-a"
	node.Spec.Gateway.Port = 19090
	node.Spec.Gateway.TrustedProxies = []string{"10.0.0.1", "10.0.0.2"}
	allowInsecureAuth := true
	dangerouslyDisableDeviceAuth := true
	node.Spec.Gateway.ControlUI = &appsv1alpha1.OpenClawControlUISpec{
		AllowInsecureAuth:            &allowInsecureAuth,
		DangerouslyDisableDeviceAuth: &dangerouslyDisableDeviceAuth,
	}
	disabled := false
	node.Spec.Chromium = &appsv1alpha1.OpenClawChromiumSpec{Enabled: &disabled}

	raw, err := renderOpenClawConfig(node)
	if err != nil {
		t.Fatalf("renderOpenClawConfig returned error: %v", err)
	}

	var config map[string]any
	if err := json.Unmarshal([]byte(raw), &config); err != nil {
		t.Fatalf("failed to parse rendered config: %v", err)
	}

	gateway := config["gateway"].(map[string]any)
	if got := gateway["port"].(float64); got != 19090 {
		t.Fatalf("unexpected gateway port: %v", got)
	}

	proxies := gateway["trustedProxies"].([]any)
	if len(proxies) != 2 {
		t.Fatalf("unexpected trusted proxies: %#v", proxies)
	}

	controlUI := gateway["controlUi"].(map[string]any)
	if got := controlUI["allowInsecureAuth"].(bool); !got {
		t.Fatalf("unexpected controlUi.allowInsecureAuth: %v", got)
	}
	if got := controlUI["dangerouslyDisableDeviceAuth"].(bool); !got {
		t.Fatalf("unexpected controlUi.dangerouslyDisableDeviceAuth: %v", got)
	}

	browser := config["browser"].(map[string]any)
	if enabled := browser["enabled"].(bool); enabled {
		t.Fatal("expected browser.enabled to be false")
	}

	session := config["session"].(map[string]any)
	if got := session["store"].(string); got != "/home/node/.openclaw/sessions.json" {
		t.Fatalf("unexpected session store path: %q", got)
	}
}

func TestRenderOpenClawConfigDefaultsTrustedProxiesToEmptyArray(t *testing.T) {
	node := &appsv1alpha1.OpenClawNode{}

	raw, err := renderOpenClawConfig(node)
	if err != nil {
		t.Fatalf("renderOpenClawConfig returned error: %v", err)
	}

	var config map[string]any
	if err := json.Unmarshal([]byte(raw), &config); err != nil {
		t.Fatalf("failed to parse rendered config: %v", err)
	}

	gateway := config["gateway"].(map[string]any)
	proxies := gateway["trustedProxies"].([]any)
	if len(proxies) != 0 {
		t.Fatalf("expected empty trusted proxies, got %#v", proxies)
	}

	controlUI := gateway["controlUi"].(map[string]any)
	if _, ok := controlUI["allowInsecureAuth"]; ok {
		t.Fatalf("expected controlUi.allowInsecureAuth to be omitted by default, got %#v", controlUI)
	}
	if _, ok := controlUI["dangerouslyDisableDeviceAuth"]; ok {
		t.Fatalf("expected controlUi.dangerouslyDisableDeviceAuth to be omitted by default, got %#v", controlUI)
	}
}

func TestInitConfigCommandDoesNotCreateSessionStoreDirectory(t *testing.T) {
	cmd := initConfigCommand()
	if strings.Contains(cmd, "/home/node/.openclaw/sessions") {
		t.Fatalf("initConfigCommand should not create a session store directory: %q", cmd)
	}
}
