// A hello world that also reports how the request reached it, so the tunnel
// test proves the whole chain rather than just the last hop.
//
// Every request is logged with both candidate client IPs side by side: the
// last X-Forwarded-For entry (what analytics/src/routes/collector.rs reads
// today) and CF-Connecting-IP (what it has to read once cloudflared is in
// front). Behind a tunnel the first is always cloudflared's bridge address,
// which is the bug decisions/0007 is about.
package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"sort"
	"strings"
)

// lastXFF is deliberately the same rule collector.rs uses: trust the last
// entry, because a normal reverse proxy appends the direct peer.
func lastXFF(r *http.Request) string {
	xff := r.Header.Get("X-Forwarded-For")
	if xff == "" {
		return "-"
	}
	parts := strings.Split(xff, ",")
	return strings.TrimSpace(parts[len(parts)-1])
}

func cfConnectingIP(r *http.Request) string {
	if ip := r.Header.Get("CF-Connecting-IP"); ip != "" {
		return ip
	}
	return "-"
}

type recorder struct {
	http.ResponseWriter
	status int
	bytes  int
}

func (w *recorder) WriteHeader(code int) {
	w.status = code
	w.ResponseWriter.WriteHeader(code)
}

func (w *recorder) Write(b []byte) (int, error) {
	if w.status == 0 {
		w.status = http.StatusOK
	}
	n, err := w.ResponseWriter.Write(b)
	w.bytes += n
	return n, err
}

func logged(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		rec := &recorder{ResponseWriter: w}
		next(rec, r)
		if rec.status == 0 {
			rec.status = http.StatusOK
		}
		via := "direct"
		if r.Header.Get("CF-Ray") != "" {
			via = "cloudflare ray=" + r.Header.Get("CF-Ray")
		}
		log.Printf("%d %s %s host=%s bytes=%d last-xff=%s cf-connecting-ip=%s %s",
			rec.status, r.Method, r.URL.Path, r.Host, rec.bytes,
			lastXFF(r), cfConnectingIP(r), via)
	}
}

func main() {
	http.HandleFunc("/healthz", logged(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, "ok")
	}))

	http.HandleFunc("/", logged(func(w http.ResponseWriter, r *http.Request) {
		// Go's "/" pattern matches every path, so without this an unknown path
		// answers 200 and the logs cannot show an error travelling the tunnel.
		if r.URL.Path != "/" {
			http.Error(w, "not found", http.StatusNotFound)
			return
		}

		var b strings.Builder
		fmt.Fprintln(&b, "Hello, world!")
		fmt.Fprintln(&b)
		fmt.Fprintf(&b, "served by  : go %s\n", os.Getenv("GO_HELLO_TAG"))
		fmt.Fprintf(&b, "host       : %s\n", r.Host)
		fmt.Fprintf(&b, "method     : %s %s %s\n", r.Method, r.URL.Path, r.Proto)
		fmt.Fprintf(&b, "remote     : %s\n", r.RemoteAddr)
		fmt.Fprintln(&b)
		fmt.Fprintln(&b, "client ip, the way each candidate rule resolves it:")
		fmt.Fprintf(&b, "  last X-Forwarded-For entry : %s   <- what collector.rs reads today\n", lastXFF(r))
		fmt.Fprintf(&b, "  CF-Connecting-IP           : %s   <- what it must read behind a tunnel\n", cfConnectingIP(r))
		fmt.Fprintln(&b)
		fmt.Fprintln(&b, "headers as the app sees them:")

		names := make([]string, 0, len(r.Header))
		for name := range r.Header {
			names = append(names, name)
		}
		sort.Strings(names)
		for _, name := range names {
			for _, v := range r.Header[name] {
				fmt.Fprintf(&b, "  %-26s %s\n", name+":", v)
			}
		}

		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		fmt.Fprint(w, b.String())
	}))

	log.Println("hello listening on :8000")
	log.Fatal(http.ListenAndServe(":8000", nil))
}
