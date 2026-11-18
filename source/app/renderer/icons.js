'use strict';

/*
 * DNS Bench icon set — inline SVG only, no external references.
 * window.Icons = { logo(size), icon(name, size, className) }
 */
(function () {
  var uid = 0;

  var paths = {
    gauge:
      '<path d="M3.6 17.1a8.6 8.6 0 1 1 16.8 0"/>' +
      '<path d="M12 15.1l3.9-4.4"/>' +
      '<circle cx="12" cy="16.3" r="1.35"/>' +
      '<path d="M6.4 11.1l1.4 1.1M12 6.9v1.8M17.6 11.1l-1.4 1.1"/>',

    list:
      '<path d="M8.6 6.4h10.8M8.6 12h10.8M8.6 17.6h10.8"/>' +
      '<circle cx="4.7" cy="6.4" r="1.05" fill="currentColor" stroke="none"/>' +
      '<circle cx="4.7" cy="12" r="1.05" fill="currentColor" stroke="none"/>' +
      '<circle cx="4.7" cy="17.6" r="1.05" fill="currentColor" stroke="none"/>',

    globe:
      '<circle cx="12" cy="12" r="8.4"/>' +
      '<path d="M3.6 12h16.8"/>' +
      '<path d="M12 3.6c2.35 2.35 3.5 5.15 3.5 8.4s-1.15 6.05-3.5 8.4c-2.35-2.35-3.5-5.15-3.5-8.4S9.65 5.95 12 3.6Z"/>',

    clock:
      '<circle cx="12" cy="12" r="8.4"/>' +
      '<path d="M12 7.4V12l3.2 2"/>',

    // Cog outline: eight rounded teeth around a hub, drawn as one path.
    gear:
      '<path d="M21.04 10.57A9.15 9.15 0 0 1 21.04 13.43L18.94 13.73A7.15 7.15 0 0 1 ' +
      '17.78 16.2L19.4 17.38A9.15 9.15 0 0 1 17.38 19.4L15.68 18.13A7.15 7.15 0 0 1 ' +
      '13.12 19.06L13.43 21.04A9.15 9.15 0 0 1 10.57 21.04L10.27 18.94A7.15 7.15 0 0 1 ' +
      '7.8 17.78L6.62 19.4A9.15 9.15 0 0 1 4.6 17.38L5.87 15.68A7.15 7.15 0 0 1 ' +
      '4.94 13.12L2.96 13.43A9.15 9.15 0 0 1 2.96 10.57L5.06 10.27A7.15 7.15 0 0 1 ' +
      '6.22 7.8L4.6 6.62A9.15 9.15 0 0 1 6.62 4.6L8.32 5.87A7.15 7.15 0 0 1 ' +
      '10.88 4.94L10.57 2.96A9.15 9.15 0 0 1 13.43 2.96L13.73 5.06A7.15 7.15 0 0 1 ' +
      '16.2 6.22L17.38 4.6A9.15 9.15 0 0 1 19.4 6.62L18.13 8.32A7.15 7.15 0 0 1 ' +
      '19.06 10.88Z"/>' +
      '<circle cx="12" cy="12" r="3.15"/>',

    play:
      '<path d="M8.5 5.9 18.1 12l-9.6 6.1z"/>',

    stop:
      '<rect x="6.2" y="6.2" width="11.6" height="11.6" rx="2.6"/>',

    export:
      '<path d="M12 15.4V4.1"/>' +
      '<path d="m8.2 7.9 3.8-3.8 3.8 3.8"/>' +
      '<path d="M5.4 14.4v3.5a2.1 2.1 0 0 0 2.1 2.1h9a2.1 2.1 0 0 0 2.1-2.1v-3.5"/>',

    refresh:
      '<path d="M20.1 11.9a8.1 8.1 0 1 1-2.4-5.7"/>' +
      '<path d="M20.1 4.3v4.6h-4.6"/>',

    check:
      '<path d="m5.4 12.4 4.2 4.2 9-9.2"/>',

    alert:
      '<path d="M12 3.9 2.8 19.2a1.5 1.5 0 0 0 1.3 2.3h15.8a1.5 1.5 0 0 0 1.3-2.3L12 3.9Z"/>' +
      '<path d="M12 9.2v4.6"/>' +
      '<circle cx="12" cy="17" r=".95" fill="currentColor" stroke="none"/>',

    chevron:
      '<path d="m9.6 5.7 6.4 6.3-6.4 6.3"/>',

    search:
      '<circle cx="10.8" cy="10.8" r="6.6"/>' +
      '<path d="m15.6 15.6 4.6 4.6"/>',

    shield:
      '<path d="M12 2.9 4.8 5.9v5.2c0 4.4 3 8 7.2 9.9 4.2-1.9 7.2-5.5 7.2-9.9V5.9L12 2.9Z"/>' +
      '<path d="m9 11.7 2.1 2.1 4-4.2"/>',

    bolt:
      '<path d="M13.5 2.7 5.4 13.4h5.2l-1 7.9 8.2-10.7h-5.2l1-7.9Z"/>',

    wifi:
      '<path d="M3.6 9.3a12.9 12.9 0 0 1 16.8 0"/>' +
      '<path d="M6.5 12.6a8.6 8.6 0 0 1 11 0"/>' +
      '<path d="M9.4 15.8a4.4 4.4 0 0 1 5.2 0"/>' +
      '<circle cx="12" cy="18.9" r="1.15" fill="currentColor" stroke="none"/>',

    server:
      '<rect x="3.4" y="4.6" width="17.2" height="6.2" rx="2.1"/>' +
      '<rect x="3.4" y="13.2" width="17.2" height="6.2" rx="2.1"/>' +
      '<circle cx="7.3" cy="7.7" r=".95" fill="currentColor" stroke="none"/>' +
      '<circle cx="7.3" cy="16.3" r=".95" fill="currentColor" stroke="none"/>' +
      '<path d="M11 7.7h6M11 16.3h6"/>',

    'arrow-up-right':
      '<path d="M6.9 17.1 17.1 6.9"/>' +
      '<path d="M8.7 6.9h8.4v8.4"/>',

    x:
      '<path d="M6.3 6.3 17.7 17.7M17.7 6.3 6.3 17.7"/>',

    info:
      '<circle cx="12" cy="12" r="8.6"/>' +
      '<path d="M12 11.1v5.1"/>' +
      '<circle cx="12" cy="7.9" r=".95" fill="currentColor" stroke="none"/>',

    external:
      '<path d="M13.7 4.4h5.9v5.9"/>' +
      '<path d="m19.3 4.7-7.5 7.5"/>' +
      '<path d="M18.4 13.9v4.5a1.9 1.9 0 0 1-1.9 1.9H5.8a1.9 1.9 0 0 1-1.9-1.9V7.7a1.9 1.9 0 0 1 1.9-1.9h4.5"/>',

    trash:
      '<path d="M4.8 6.6h14.4"/>' +
      '<path d="M9.2 6.6V4.9a1.4 1.4 0 0 1 1.4-1.4h2.8a1.4 1.4 0 0 1 1.4 1.4v1.7"/>' +
      '<path d="m6.5 6.6.9 12.1a2 2 0 0 0 2 1.9h5.2a2 2 0 0 0 2-1.9l.9-12.1"/>' +
      '<path d="M10.3 10.4v6M13.7 10.4v6"/>',

    sparkles:
      '<path d="M12 3.2c.7 3.5 2.1 4.9 5.6 5.6-3.5.7-4.9 2.1-5.6 5.6-.7-3.5-2.1-4.9-5.6-5.6 3.5-.7 4.9-2.1 5.6-5.6Z"/>' +
      '<path d="M18.2 14.7c.35 1.75 1.05 2.45 2.8 2.8-1.75.35-2.45 1.05-2.8 2.8-.35-1.75-1.05-2.45-2.8-2.8 1.75-.35 2.45-1.05 2.8-2.8Z"/>',

    lock:
      '<rect x="5.2" y="10.3" width="13.6" height="10" rx="2.6"/>' +
      '<path d="M8.3 10.3V7.8a3.7 3.7 0 0 1 7.4 0v2.5"/>' +
      '<circle cx="12" cy="15.2" r="1.15" fill="currentColor" stroke="none"/>',

    cpu:
      '<rect x="7" y="7" width="10" height="10" rx="2.2"/>' +
      '<rect x="10.2" y="10.2" width="3.6" height="3.6" rx="1"/>' +
      '<path d="M10 7V4.1M14 7V4.1M10 19.9V17M14 19.9V17M7 10H4.1M7 14H4.1M19.9 10H17M19.9 14H17"/>',

    network:
      '<circle cx="12" cy="5.6" r="2.3"/>' +
      '<circle cx="5.7" cy="18.2" r="2.3"/>' +
      '<circle cx="18.3" cy="18.2" r="2.3"/>' +
      '<path d="M12 7.9v3.1M10.6 12.4 7.3 16.1M13.4 12.4l3.3 3.7"/>' +
      '<circle cx="12" cy="12" r="1" fill="currentColor" stroke="none"/>',

    download:
      '<path d="M12 4v11.2"/>' +
      '<path d="m7.6 11 4.4 4.4 4.4-4.4"/>' +
      '<path d="M5.5 19.6h13"/>',

    // Helpful extras used by detail panes.
    copy:
      '<rect x="8.6" y="8.6" width="10.6" height="10.6" rx="2.2"/>' +
      '<path d="M15.4 5.4a2.2 2.2 0 0 0-2.2-2.2H6a2.2 2.2 0 0 0-2.2 2.2v7.2a2.2 2.2 0 0 0 2.2 2.2"/>',

    link:
      '<path d="M10.2 13.8a3.6 3.6 0 0 0 5.1 0l3-3a3.6 3.6 0 0 0-5.1-5.1l-1.6 1.6"/>' +
      '<path d="M13.8 10.2a3.6 3.6 0 0 0-5.1 0l-3 3a3.6 3.6 0 0 0 5.1 5.1l1.6-1.6"/>',

    activity:
      '<path d="M3.6 12h3.6l2.4-6.4 4.2 12.8 2.2-6.4h4.4"/>',

    router:
      '<rect x="3.4" y="12.4" width="17.2" height="6.4" rx="2.2"/>' +
      '<path d="M8 4.2 12 8l4-3.8"/>' +
      '<path d="M12 8v3.2"/>' +
      '<circle cx="7.2" cy="15.6" r=".95" fill="currentColor" stroke="none"/>',

    'chevron-down':
      '<path d="m6.4 9.4 5.6 5.6 5.6-5.6"/>',

    'chevron-up':
      '<path d="m6.4 14.6 5.6-5.6 5.6 5.6"/>'
  };

  function cleanClass(className) {
    if (!className) return '';
    var value = String(className).replace(/[^\w\s-]/g, '').trim();
    return value ? ' ' + value : '';
  }

  function icon(name, size, className) {
    var body = paths[name];
    if (!body) body = paths.info;
    var px = Math.max(1, Number(size) || 18);
    return '<svg class="icon' + cleanClass(className) + '" width="' + px + '" height="' + px + '"' +
      ' viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"' +
      ' stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">' +
      body + '</svg>';
  }

  function logo(size) {
    var px = Math.max(1, Number(size) || 28);
    var id = 'dnsb-logo-' + (++uid);
    return '<svg class="app-logo" width="' + px + '" height="' + px + '"' +
      ' viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg"' +
      ' aria-hidden="true" focusable="false">' +
      '<defs>' +
        '<linearGradient id="' + id + '" x1="5" y1="2.4" x2="27" y2="30.6" gradientUnits="userSpaceOnUse">' +
          '<stop stop-color="#7fe3ff"/>' +
          '<stop offset=".42" stop-color="#3b9cff"/>' +
          '<stop offset="1" stop-color="#5759e6"/>' +
        '</linearGradient>' +
        '<radialGradient id="' + id + '-sheen" cx="0" cy="0" r="1" gradientUnits="userSpaceOnUse"' +
          ' gradientTransform="translate(8.4 5.2) rotate(48) scale(23 15)">' +
          '<stop stop-color="#ffffff" stop-opacity=".5"/>' +
          '<stop offset="1" stop-color="#ffffff" stop-opacity="0"/>' +
        '</radialGradient>' +
        '<linearGradient id="' + id + '-edge" x1="16" y1="1.8" x2="16" y2="30.2" gradientUnits="userSpaceOnUse">' +
          '<stop stop-color="#ffffff" stop-opacity=".55"/>' +
          '<stop offset=".5" stop-color="#ffffff" stop-opacity=".08"/>' +
          '<stop offset="1" stop-color="#ffffff" stop-opacity=".2"/>' +
        '</linearGradient>' +
      '</defs>' +
      '<path d="M16 1.8c10.3 0 14.2 3.9 14.2 14.2S26.3 30.2 16 30.2 1.8 26.3 1.8 16 5.7 1.8 16 1.8Z" fill="url(#' + id + ')"/>' +
      '<path d="M16 1.8c10.3 0 14.2 3.9 14.2 14.2S26.3 30.2 16 30.2 1.8 26.3 1.8 16 5.7 1.8 16 1.8Z" fill="url(#' + id + '-sheen)"/>' +
      '<rect x="8.3" y="16.4" width="3.6" height="7.8" rx="1.8" fill="#ffffff" opacity=".94"/>' +
      '<rect x="14.2" y="12.2" width="3.6" height="12" rx="1.8" fill="#ffffff" opacity=".97"/>' +
      '<rect x="20.1" y="8" width="3.6" height="16.2" rx="1.8" fill="#ffffff"/>' +
      '<circle cx="24.9" cy="5.9" r="1.45" fill="#ffffff" opacity=".9"/>' +
      '<path d="M16 1.8c10.3 0 14.2 3.9 14.2 14.2S26.3 30.2 16 30.2 1.8 26.3 1.8 16 5.7 1.8 16 1.8Z" stroke="url(#' + id + '-edge)" stroke-width=".9"/>' +
      '<path d="M4.4 10.6c1.1-3.7 4.1-6.4 7.9-7.2" stroke="#ffffff" stroke-opacity=".3" stroke-width="1.1" stroke-linecap="round"/>' +
    '</svg>';
  }

  window.Icons = { logo: logo, icon: icon, names: Object.keys(paths) };
})();
