package main

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// stub backend that returns 200 for everything forwarded to it.
var stubBackend = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	io.WriteString(w, "OK")
})

func testHandler() http.Handler {
	return newHandler(stubBackend)
}

func registerChild(id string) {
	createdContainers.Lock()
	createdContainers.ids[id] = true
	createdContainers.Unlock()
}

func clearChildren() {
	createdContainers.Lock()
	createdContainers.ids = make(map[string]bool)
	createdContainers.Unlock()
}

// --- Allowlist: blocked by default ---

func TestUnknownEndpoint_Blocked(t *testing.T) {
	h := testHandler()
	for _, path := range []string{
		"/build",
		"/commit",
		"/plugins",
		"/plugins/someplugin/enable",
		"/swarm/init",
		"/services/create",
		"/nodes",
		"/secrets",
		"/configs",
		"/unknown/endpoint",
	} {
		w := httptest.NewRecorder()
		h.ServeHTTP(w, httptest.NewRequest("POST", path, nil))
		if w.Code != http.StatusForbidden {
			t.Errorf("%s: expected 403, got %d", path, w.Code)
		}
	}
}

func TestSystemEndpoints_Allowed(t *testing.T) {
	h := testHandler()
	for _, path := range []string{"/_ping", "/version", "/info", "/events"} {
		w := httptest.NewRecorder()
		h.ServeHTTP(w, httptest.NewRequest("GET", path, nil))
		if w.Code != http.StatusOK {
			t.Errorf("GET %s: expected 200, got %d", path, w.Code)
		}
	}
}

func TestVersionedEndpoints_Allowed(t *testing.T) {
	h := testHandler()
	for _, path := range []string{"/v1.41/_ping", "/v1.45/containers/json", "/v5.4.2/version"} {
		w := httptest.NewRecorder()
		h.ServeHTTP(w, httptest.NewRequest("GET", path, nil))
		if w.Code != http.StatusOK {
			t.Errorf("GET %s: expected 200, got %d", path, w.Code)
		}
	}
}

func TestSystemEndpoints_WrongMethod(t *testing.T) {
	h := testHandler()
	w := httptest.NewRecorder()
	h.ServeHTTP(w, httptest.NewRequest("DELETE", "/_ping", nil))
	if w.Code != http.StatusForbidden {
		t.Errorf("DELETE /_ping: expected 403, got %d", w.Code)
	}
}

// --- Container lifecycle: child-only ---

func TestContainerActions_BlockedOnSandbox(t *testing.T) {
	clearChildren()
	h := testHandler()
	actions := []struct {
		method, path string
	}{
		{"POST", "/containers/sandbox123/start"},
		{"POST", "/containers/sandbox123/stop"},
		{"POST", "/containers/sandbox123/kill"},
		{"POST", "/containers/sandbox123/restart"},
		{"POST", "/containers/sandbox123/pause"},
		{"POST", "/containers/sandbox123/unpause"},
		{"POST", "/containers/sandbox123/wait"},
		{"POST", "/containers/sandbox123/resize"},
		{"POST", "/containers/sandbox123/rename"},
		{"POST", "/containers/sandbox123/exec"},
		{"POST", "/containers/sandbox123/attach"},
		{"GET", "/containers/sandbox123/archive?path=/etc"},
		{"PUT", "/containers/sandbox123/archive?path=/tmp"},
		{"GET", "/containers/sandbox123/logs"},
		{"DELETE", "/containers/sandbox123"},
	}
	for _, a := range actions {
		w := httptest.NewRecorder()
		h.ServeHTTP(w, httptest.NewRequest(a.method, a.path, nil))
		if w.Code != http.StatusForbidden {
			t.Errorf("%s %s: expected 403, got %d", a.method, a.path, w.Code)
		}
	}
}

func TestContainerActions_AllowedOnChild(t *testing.T) {
	clearChildren()
	registerChild("child456")
	h := testHandler()
	actions := []struct {
		method, path string
	}{
		{"POST", "/containers/child456/start"},
		{"POST", "/containers/child456/stop"},
		{"POST", "/containers/child456/kill"},
		{"POST", "/containers/child456/restart"},
		{"POST", "/containers/child456/wait"},
		{"POST", "/containers/child456/rename"},
		{"POST", "/containers/child456/exec"},
		{"POST", "/containers/child456/attach"},
		{"GET", "/containers/child456/archive?path=/tmp"},
		{"GET", "/containers/child456/logs"},
		{"DELETE", "/containers/child456"},
	}
	for _, a := range actions {
		w := httptest.NewRecorder()
		h.ServeHTTP(w, httptest.NewRequest(a.method, a.path, nil))
		if w.Code != http.StatusOK {
			t.Errorf("%s %s: expected 200, got %d", a.method, a.path, w.Code)
		}
	}
}

// --- Container inspect/list — allowed without child check ---

func TestContainerInspect_Allowed(t *testing.T) {
	clearChildren()
	h := testHandler()
	for _, path := range []string{"/containers/json", "/containers/anyid/json"} {
		w := httptest.NewRecorder()
		h.ServeHTTP(w, httptest.NewRequest("GET", path, nil))
		if w.Code != http.StatusOK {
			t.Errorf("GET %s: expected 200, got %d", path, w.Code)
		}
	}
}

// --- Versioned paths ---

func TestVersionedArchive_BlockedOnSandbox(t *testing.T) {
	clearChildren()
	h := testHandler()
	w := httptest.NewRecorder()
	h.ServeHTTP(w, httptest.NewRequest("GET", "/v1.45/containers/sandbox123/archive?path=/etc", nil))
	if w.Code != http.StatusForbidden {
		t.Errorf("expected 403 for versioned path, got %d", w.Code)
	}
}

// --- Images ---

func TestImageEndpoints_Allowed(t *testing.T) {
	h := testHandler()
	cases := []struct {
		method, path string
	}{
		{"POST", "/images/create"},
		{"GET", "/images/json"},
		{"GET", "/images/mongo:7/json"},
		{"DELETE", "/images/oldimage"},
	}
	for _, c := range cases {
		w := httptest.NewRecorder()
		h.ServeHTTP(w, httptest.NewRequest(c.method, c.path, nil))
		if w.Code != http.StatusOK {
			t.Errorf("%s %s: expected 200, got %d", c.method, c.path, w.Code)
		}
	}
}

// --- Networks ---

func TestNetworkEndpoints_Allowed(t *testing.T) {
	h := testHandler()
	cases := []struct {
		method, path string
	}{
		{"GET", "/networks"},
		{"GET", "/networks/mynet"},
		{"DELETE", "/networks/mynet"},
		{"POST", "/networks/mynet/connect"},
		{"POST", "/networks/mynet/disconnect"},
	}
	for _, c := range cases {
		w := httptest.NewRecorder()
		h.ServeHTTP(w, httptest.NewRequest(c.method, c.path, nil))
		if w.Code != http.StatusOK {
			t.Errorf("%s %s: expected 200, got %d", c.method, c.path, w.Code)
		}
	}
}

func TestNetworkCreate_BlocksDangerousDrivers(t *testing.T) {
	h := testHandler()
	for _, driver := range []string{"host", "macvlan", "ipvlan"} {
		body := `{"Driver":"` + driver + `","Name":"evil"}`
		req := httptest.NewRequest("POST", "/networks/create", strings.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()
		h.ServeHTTP(w, req)
		if w.Code != http.StatusForbidden {
			t.Errorf("network driver %q: expected 403, got %d", driver, w.Code)
		}
	}
}

func TestNetworkCreate_AllowsBridge(t *testing.T) {
	h := testHandler()
	body := `{"Driver":"bridge","Name":"testnet"}`
	req := httptest.NewRequest("POST", "/networks/create", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	h.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Errorf("bridge network: expected 200, got %d", w.Code)
	}
}

// --- Volumes ---

func TestVolumeEndpoints_Allowed(t *testing.T) {
	h := testHandler()
	cases := []struct {
		method, path string
	}{
		{"POST", "/volumes/create"},
		{"GET", "/volumes"},
		{"GET", "/volumes/myvol"},
		{"DELETE", "/volumes/myvol"},
	}
	for _, c := range cases {
		w := httptest.NewRecorder()
		h.ServeHTTP(w, httptest.NewRequest(c.method, c.path, nil))
		if w.Code != http.StatusOK {
			t.Errorf("%s %s: expected 200, got %d", c.method, c.path, w.Code)
		}
	}
}

// --- Exec ---

func TestExecEndpoints_Allowed(t *testing.T) {
	h := testHandler()
	cases := []struct {
		method, path string
	}{
		{"POST", "/exec/execid123/start"},
		{"POST", "/exec/execid123/resize"},
		{"GET", "/exec/execid123/json"},
	}
	for _, c := range cases {
		w := httptest.NewRecorder()
		h.ServeHTTP(w, httptest.NewRequest(c.method, c.path, nil))
		if w.Code != http.StatusOK {
			t.Errorf("%s %s: expected 200, got %d", c.method, c.path, w.Code)
		}
	}
}

// --- checkHostConfig tests (unchanged from before) ---

func TestCheckHostConfig_AllowsPlainContainer(t *testing.T) {
	config := map[string]interface{}{
		"Image": "mongo:7",
		"HostConfig": map[string]interface{}{
			"PortBindings": map[string]interface{}{},
		},
	}
	if err := checkHostConfig(config); err != nil {
		t.Errorf("expected plain container to be allowed, got: %v", err)
	}
}

func TestCheckHostConfig_BlocksPrivileged(t *testing.T) {
	config := map[string]interface{}{
		"HostConfig": map[string]interface{}{
			"Privileged": true,
		},
	}
	if err := checkHostConfig(config); err == nil {
		t.Error("expected privileged to be blocked")
	}
}

func TestCheckHostConfig_BlocksHostPathBinds(t *testing.T) {
	config := map[string]interface{}{
		"HostConfig": map[string]interface{}{
			"Binds": []interface{}{"/host/path:/container/path"},
		},
	}
	if err := checkHostConfig(config); err == nil {
		t.Error("expected host path bind to be blocked")
	}
}

func TestCheckHostConfig_AllowsNamedVolumes(t *testing.T) {
	config := map[string]interface{}{
		"HostConfig": map[string]interface{}{
			"Binds": []interface{}{"myvolume:/data"},
		},
	}
	if err := checkHostConfig(config); err != nil {
		t.Errorf("expected named volume to be allowed, got: %v", err)
	}
}

func TestCheckHostConfig_BlocksHostBindMounts(t *testing.T) {
	config := map[string]interface{}{
		"HostConfig": map[string]interface{}{
			"Mounts": []interface{}{
				map[string]interface{}{
					"Type":   "bind",
					"Source": "/etc/shadow",
					"Target": "/mnt/shadow",
				},
			},
		},
	}
	if err := checkHostConfig(config); err == nil {
		t.Error("expected host bind mount to be blocked")
	}
}

func TestCheckHostConfig_AllowsVolumeMounts(t *testing.T) {
	config := map[string]interface{}{
		"HostConfig": map[string]interface{}{
			"Mounts": []interface{}{
				map[string]interface{}{
					"Type":   "volume",
					"Source": "mydata",
					"Target": "/data",
				},
			},
		},
	}
	if err := checkHostConfig(config); err != nil {
		t.Errorf("expected volume mount to be allowed, got: %v", err)
	}
}

func TestCheckHostConfig_BlocksHostPID(t *testing.T) {
	config := map[string]interface{}{
		"HostConfig": map[string]interface{}{
			"PidMode": "host",
		},
	}
	if err := checkHostConfig(config); err == nil {
		t.Error("expected host PID to be blocked")
	}
}

func TestCheckHostConfig_BlocksHostNetwork(t *testing.T) {
	config := map[string]interface{}{
		"HostConfig": map[string]interface{}{
			"NetworkMode": "host",
		},
	}
	if err := checkHostConfig(config); err == nil {
		t.Error("expected host network to be blocked")
	}
}

func TestCheckHostConfig_BlocksHostIPC(t *testing.T) {
	config := map[string]interface{}{
		"HostConfig": map[string]interface{}{
			"IpcMode": "host",
		},
	}
	if err := checkHostConfig(config); err == nil {
		t.Error("expected host IPC to be blocked")
	}
}

func TestCheckHostConfig_BlocksPidModeNonChild(t *testing.T) {
	clearChildren()
	config := map[string]interface{}{
		"HostConfig": map[string]interface{}{
			"PidMode": "container:sandbox123",
		},
	}
	if err := checkHostConfig(config); err == nil {
		t.Error("expected PidMode sharing with non-child container to be blocked")
	}
}

func TestCheckHostConfig_AllowsPidModeChild(t *testing.T) {
	clearChildren()
	registerChild("child456")
	config := map[string]interface{}{
		"HostConfig": map[string]interface{}{
			"PidMode": "container:child456",
		},
	}
	if err := checkHostConfig(config); err != nil {
		t.Errorf("expected PidMode sharing with child to be allowed, got: %v", err)
	}
}

func TestCheckHostConfig_BlocksIpcModeNonChild(t *testing.T) {
	clearChildren()
	config := map[string]interface{}{
		"HostConfig": map[string]interface{}{
			"IpcMode": "container:sandbox123",
		},
	}
	if err := checkHostConfig(config); err == nil {
		t.Error("expected IpcMode sharing with non-child container to be blocked")
	}
}

func TestCheckHostConfig_AllowsIpcModeChild(t *testing.T) {
	clearChildren()
	registerChild("child456")
	config := map[string]interface{}{
		"HostConfig": map[string]interface{}{
			"IpcMode": "container:child456",
		},
	}
	if err := checkHostConfig(config); err != nil {
		t.Errorf("expected IpcMode sharing with child to be allowed, got: %v", err)
	}
}

func TestCheckHostConfig_BlocksHostUTS(t *testing.T) {
	config := map[string]interface{}{
		"HostConfig": map[string]interface{}{
			"UTSMode": "host",
		},
	}
	if err := checkHostConfig(config); err == nil {
		t.Error("expected UTSMode=host to be blocked")
	}
}

func TestCheckHostConfig_BlocksUsernsHost(t *testing.T) {
	config := map[string]interface{}{
		"HostConfig": map[string]interface{}{
			"UsernsMode": "host",
		},
	}
	if err := checkHostConfig(config); err == nil {
		t.Error("expected UsernsMode=host to be blocked")
	}
}

func TestCheckHostConfig_BlocksUsernsNonChild(t *testing.T) {
	clearChildren()
	config := map[string]interface{}{
		"HostConfig": map[string]interface{}{
			"UsernsMode": "container:sandbox123",
		},
	}
	if err := checkHostConfig(config); err == nil {
		t.Error("expected UsernsMode sharing with non-child container to be blocked")
	}
}

func TestCheckHostConfig_AllowsUsernsChild(t *testing.T) {
	clearChildren()
	registerChild("child456")
	config := map[string]interface{}{
		"HostConfig": map[string]interface{}{
			"UsernsMode": "container:child456",
		},
	}
	if err := checkHostConfig(config); err != nil {
		t.Errorf("expected UsernsMode sharing with child to be allowed, got: %v", err)
	}
}

func TestCheckHostConfig_BlocksSysctls(t *testing.T) {
	config := map[string]interface{}{
		"HostConfig": map[string]interface{}{
			"Sysctls": map[string]interface{}{
				"net.ipv4.ip_forward": "1",
			},
		},
	}
	if err := checkHostConfig(config); err == nil {
		t.Error("expected Sysctls to be blocked")
	}
}

func TestCheckHostConfig_BlocksTmpfs(t *testing.T) {
	config := map[string]interface{}{
		"HostConfig": map[string]interface{}{
			"Tmpfs": map[string]interface{}{
				"/proc": "rw,exec",
			},
		},
	}
	if err := checkHostConfig(config); err == nil {
		t.Error("expected Tmpfs mount to be blocked")
	}
}

func TestCheckHostConfig_BlocksNetRaw(t *testing.T) {
	config := map[string]interface{}{
		"HostConfig": map[string]interface{}{
			"CapAdd": []interface{}{"NET_RAW"},
		},
	}
	if err := checkHostConfig(config); err == nil {
		t.Error("expected NET_RAW capability to be blocked")
	}
}

func TestCheckHostConfig_BlocksSysAdmin(t *testing.T) {
	config := map[string]interface{}{
		"HostConfig": map[string]interface{}{
			"CapAdd": []interface{}{"SYS_ADMIN"},
		},
	}
	if err := checkHostConfig(config); err == nil {
		t.Error("expected SYS_ADMIN capability to be blocked")
	}
}

func TestCheckHostConfig_BlocksCapAll(t *testing.T) {
	config := map[string]interface{}{
		"HostConfig": map[string]interface{}{
			"CapAdd": []interface{}{"ALL"},
		},
	}
	if err := checkHostConfig(config); err == nil {
		t.Error("expected ALL capability to be blocked")
	}
}

func TestCheckHostConfig_AllowsSafeCapabilities(t *testing.T) {
	config := map[string]interface{}{
		"HostConfig": map[string]interface{}{
			"CapAdd": []interface{}{"NET_BIND_SERVICE"},
		},
	}
	if err := checkHostConfig(config); err != nil {
		t.Errorf("expected safe capability to be allowed, got: %v", err)
	}
}

func TestCheckHostConfig_BlocksSysPtrace(t *testing.T) {
	config := map[string]interface{}{
		"HostConfig": map[string]interface{}{
			"CapAdd": []interface{}{"SYS_PTRACE"},
		},
	}
	if err := checkHostConfig(config); err == nil {
		t.Error("expected SYS_PTRACE capability to be blocked")
	}
}

func TestCheckHostConfig_BlocksDevices(t *testing.T) {
	config := map[string]interface{}{
		"HostConfig": map[string]interface{}{
			"Devices": []interface{}{
				map[string]interface{}{
					"PathOnHost":        "/dev/sda",
					"PathInContainer":   "/dev/sda",
					"CgroupPermissions": "rwm",
				},
			},
		},
	}
	if err := checkHostConfig(config); err == nil {
		t.Error("expected device mapping to be blocked")
	}
}

func TestCheckHostConfig_BlocksSeccompUnconfined(t *testing.T) {
	config := map[string]interface{}{
		"HostConfig": map[string]interface{}{
			"SecurityOpt": []interface{}{"seccomp=unconfined"},
		},
	}
	if err := checkHostConfig(config); err == nil {
		t.Error("expected seccomp=unconfined to be blocked")
	}
}

func TestCheckHostConfig_BlocksApparmorUnconfined(t *testing.T) {
	config := map[string]interface{}{
		"HostConfig": map[string]interface{}{
			"SecurityOpt": []interface{}{"apparmor=unconfined"},
		},
	}
	if err := checkHostConfig(config); err == nil {
		t.Error("expected apparmor=unconfined to be blocked")
	}
}

func TestCheckHostConfig_BlocksRelativePathBinds(t *testing.T) {
	config := map[string]interface{}{
		"HostConfig": map[string]interface{}{
			"Binds": []interface{}{"../../../etc:/mnt/host:ro"},
		},
	}
	if err := checkHostConfig(config); err == nil {
		t.Error("expected relative path bind to be blocked")
	}
}

func TestCheckHostConfig_BlocksDotPathBinds(t *testing.T) {
	config := map[string]interface{}{
		"HostConfig": map[string]interface{}{
			"Binds": []interface{}{"./localdir:/mnt"},
		},
	}
	if err := checkHostConfig(config); err == nil {
		t.Error("expected dot-relative path bind to be blocked")
	}
}

func TestCheckHostConfig_BlocksTildeBinds(t *testing.T) {
	config := map[string]interface{}{
		"HostConfig": map[string]interface{}{
			"Binds": []interface{}{"~:/mnt/home"},
		},
	}
	if err := checkHostConfig(config); err == nil {
		t.Error("expected tilde path bind to be blocked")
	}
}

func TestCheckHostConfig_BlocksAllBindMountsInMounts(t *testing.T) {
	config := map[string]interface{}{
		"HostConfig": map[string]interface{}{
			"Mounts": []interface{}{
				map[string]interface{}{
					"Type":   "bind",
					"Source": "relative/path",
					"Target": "/mnt",
				},
			},
		},
	}
	if err := checkHostConfig(config); err == nil {
		t.Error("expected bind mount in Mounts array to be blocked")
	}
}

func TestCheckHostConfig_NoHostConfig(t *testing.T) {
	config := map[string]interface{}{
		"Image": "mongo:7",
	}
	if err := checkHostConfig(config); err != nil {
		t.Errorf("expected no HostConfig to be allowed, got: %v", err)
	}
}
