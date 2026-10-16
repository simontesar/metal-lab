package ignitionshim

import "testing"

func TestDecodeConfig(t *testing.T) {
	tests := []struct {
		name    string
		doc     string
		want    Config
		wantErr bool
	}{
		{
			name: "discovery document with flags",
			doc:  `{"ignition":{"version":"3.4.0"},"storage":{"files":[{"path":"/metalprobe/config","contents":{"source":"data:,--registry-url%3Dhttp%3A%2F%2F10.250.200.2%3A30000%20--server-uuid%3D1"}}]}}`,
			want: Config{Flags: "--registry-url=http://10.250.200.2:30000 --server-uuid=1"},
		},
		{
			name: "empty document",
			doc:  `{"ignition":{"version":"3.4.0"}}`,
			want: Config{},
		},
		{
			name: "ignore power button",
			doc:  `{"ignition":{"version":"3.4.0"},"storage":{"files":[{"path":"/metalprobe/ignore-power-button","contents":{"source":"data:,"}}]}}`,
			want: Config{IgnorePowerButton: true},
		},
		{
			name:    "invalid json",
			doc:     `{`,
			wantErr: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := decodeConfig([]byte(tt.doc))
			if (err != nil) != tt.wantErr {
				t.Fatalf("decodeConfig() error = %v, wantErr %v", err, tt.wantErr)
			}
			if err == nil && *got != tt.want {
				t.Errorf("decodeConfig() = %+v, want %+v", *got, tt.want)
			}
		})
	}
}
