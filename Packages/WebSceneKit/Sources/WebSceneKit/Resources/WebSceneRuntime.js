// WebSceneKit JS Runtime — injected at documentStart into every WebSceneView.
// Provides a typed, idempotent bridge between Swift and JS.
//
// JS API:
//   window.WebScene.onCommand((cmd) => { ... })   // register command listener
//   window.WebScene.postEvent(type, payload)       // send event to Swift
//   window.WebScene.ready()                        // signal the scene is ready
//   window.WebScene.enableFPSReporting(intervalMs) // optional FPS stream
//   window.WebScene.isEmbedded                     // true when hosted
(function () {
  'use strict';
  if (window.WebScene && window.__WebSceneRuntime) return;

  var BRIDGE_NAME = "__WEBSCENE_BRIDGE_NAME__";
  var handlers = [];
  var readySent = false;
  var earlyCommandQueue = [];
  var fpsTimer = null;

  function post(envelope) {
    try {
      var mh = window.webkit &&
        window.webkit.messageHandlers &&
        window.webkit.messageHandlers[BRIDGE_NAME];
      if (mh && typeof mh.postMessage === 'function') {
        mh.postMessage(envelope);
      }
    } catch (e) {
      // Silently swallow — bridge not available (e.g., loaded in a regular browser for dev).
    }
  }

  function dispatch(command) {
    if (!command || typeof command !== 'object') return;
    // If handlers aren't registered yet, buffer the command.
    if (handlers.length === 0) {
      earlyCommandQueue.push(command);
      return;
    }
    for (var i = 0; i < handlers.length; i++) {
      try {
        handlers[i](command);
      } catch (err) {
        post({
          type: '__error',
          payload: {
            source: 'command',
            type: command.type,
            message: String((err && err.message) || err),
          },
        });
      }
    }
  }

  var api = {
    isEmbedded: true,
    bridgeName: BRIDGE_NAME,

    onCommand: function (handler) {
      if (typeof handler !== 'function') return function () {};
      handlers.push(handler);
      // Flush any commands that arrived before the handler registered.
      if (earlyCommandQueue.length > 0) {
        var queued = earlyCommandQueue.slice();
        earlyCommandQueue.length = 0;
        for (var i = 0; i < queued.length; i++) {
          try { handler(queued[i]); } catch (_) {}
        }
      }
      return function () {
        var idx = handlers.indexOf(handler);
        if (idx !== -1) handlers.splice(idx, 1);
      };
    },

    postEvent: function (type, payload) {
      if (typeof type !== 'string') return;
      post({ type: type, payload: payload || {} });
    },

    ready: function () {
      if (readySent) return;
      readySent = true;
      post({ type: '__ready', payload: {} });
    },

    enableFPSReporting: function (intervalMs) {
      if (fpsTimer) return;
      intervalMs = intervalMs || 1000;
      var frames = 0;
      var last = performance.now();
      function tick() {
        frames++;
        requestAnimationFrame(tick);
      }
      requestAnimationFrame(tick);
      fpsTimer = setInterval(function () {
        var now = performance.now();
        var elapsed = (now - last) / 1000;
        if (elapsed <= 0) return;
        var fps = frames / elapsed;
        frames = 0;
        last = now;
        post({ type: '__fps', payload: { value: Math.round(fps * 10) / 10 } });
      }, intervalMs);
    },

    disableFPSReporting: function () {
      if (fpsTimer) {
        clearInterval(fpsTimer);
        fpsTimer = null;
      }
    },
  };

  // Internal dispatch entrypoint called by Swift-side evaluateJavaScript.
  window.__WebSceneRuntime = {
    dispatch: dispatch,
    version: '1.0.0',
  };

  window.WebScene = api;
  // Announce runtime availability immediately so Swift can distinguish "runtime missing"
  // from "scene script hasn't reached ready()".
  post({ type: '__runtimeReady', payload: { version: '1.0.0' } });

  // Forward uncaught errors to Swift.
  window.addEventListener('error', function (e) {
    post({
      type: '__error',
      payload: {
        source: 'window',
        message: (e && e.message) || 'Unknown error',
        filename: e && e.filename,
        lineno: e && e.lineno,
      },
    });
  });
  window.addEventListener('unhandledrejection', function (e) {
    var reason = e && e.reason;
    post({
      type: '__error',
      payload: {
        source: 'promise',
        message: reason && reason.message ? reason.message : String(reason),
        stack: reason && reason.stack ? String(reason.stack) : null,
      },
    });
  });

  // Mirror console output to Swift as __log events. Preserves original console.
  try {
    ['log', 'warn', 'error', 'info'].forEach(function (level) {
      var orig = console[level] ? console[level].bind(console) : function () {};
      console[level] = function () {
        try {
          var args = Array.prototype.slice.call(arguments).map(function (a) {
            if (a === null || a === undefined) return String(a);
            if (typeof a === 'string') return a;
            try { return JSON.stringify(a); } catch (_) { return String(a); }
          });
          post({ type: '__log', payload: { level: level, message: args.join(' ') } });
        } catch (_) {}
        orig.apply(console, arguments);
      };
    });
  } catch (_) {}

  // Optimization hint: prevent overscroll / rubber-band bounce on iOS when a page
  // forgets to set overflow:hidden. Cheap and idempotent.
  try {
    document.addEventListener('DOMContentLoaded', function () {
      var root = document.documentElement;
      var body = document.body;
      if (root) root.style.overscrollBehavior = 'none';
      if (body) body.style.overscrollBehavior = 'none';
    });
  } catch (_) {}
})();
