import React from "react";
import { Component } from "react";
import type { ErrorInfo, ReactNode } from "react";
import ReactDOM from "react-dom/client";
import App from "./App";

type AppErrorBoundaryState = {
  error: Error | null;
};

class AppErrorBoundary extends Component<{ children: ReactNode }, AppErrorBoundaryState> {
  state: AppErrorBoundaryState = { error: null };

  static getDerivedStateFromError(error: Error): AppErrorBoundaryState {
    return { error };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error("NekoFM render error", error, info.componentStack);
  }

  render() {
    if (this.state.error) {
      return (
        <main className="app-error-shell">
          <section className="app-error-panel">
            <div className="app-mark" aria-label="NekoFM">
              <span aria-hidden="true">N</span>
            </div>
            <div>
              <h1>NekoFM hit a screen error</h1>
              <p>
                Reload the app to recover. The console keeps the technical details for debugging.
              </p>
            </div>
            <pre>{this.state.error.message}</pre>
            <button type="button" onClick={() => window.location.reload()}>
              Reload
            </button>
          </section>
        </main>
      );
    }

    return this.props.children;
  }
}

ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <React.StrictMode>
    <AppErrorBoundary>
      <App />
    </AppErrorBoundary>
  </React.StrictMode>,
);
