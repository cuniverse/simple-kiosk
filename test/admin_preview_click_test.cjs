// Run with: node test/admin_preview_click_test.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const html = fs.readFileSync(path.join(__dirname, '../assets/admin/index.html'), 'utf8');
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];
new vm.Script(script); // Check the whole admin script for syntax errors.
const functions = script.slice(script.indexOf('function screenPreviewCoordinates('),
  script.indexOf("$('screenPreviewImage').addEventListener('pointerdown'"));
const requests = [];
const notices = [];
const timers = new Map();
let timerId = 0;
let capturedPointer = null;
const image = {
  dataset: {clickable: 'true', frameId: 'frame-1'},
  naturalWidth: 1080, naturalHeight: 1920,
  getBoundingClientRect: () => ({left: 100, top: 50, width: 800, height: 450}),
  setPointerCapture: id => capturedPointer = id,
  hasPointerCapture: id => capturedPointer === id,
  releasePointerCapture: () => capturedPointer = null,
};
const context = vm.createContext({
  $: () => image, token: 'admin-token', previewActive: true,
  activeAdminTab: 'preview', document: {hidden: false},
  AbortController,
  setTimeout: (fn, ms) => {timers.set(++timerId, {fn, ms}); return timerId;},
  clearTimeout: id => timers.delete(id),
  setInterval: (fn, ms) => {timers.set(++timerId, {fn, ms}); return timerId;},
  clearInterval: id => timers.delete(id),
  fetch: async (...args) => {
    requests.push(args);
    return {ok: true, json: async () => ({ok: true})};
  },
  scheduleScreenPreview: () => {},
  message: text => notices.push(text),
  requireReauthentication: () => {},
});
vm.runInContext(functions, context);
const settle = () => new Promise(resolve => setImmediate(resolve));
const phases = () => requests.map(request => JSON.parse(request[1].body).phase);

async function verify() {
  const coords = context.screenPreviewCoordinates;
  const rect = {left: 100, top: 50, width: 800, height: 450};
  const center = coords(rect, 1080, 1920, 500, 275);
  assert.equal(center.x, 0.5);
  assert.equal(center.y, 0.5);
  assert.equal(coords(rect, 1080, 1920, 110, 275), null); // Side letterbox.
  assert.equal(coords({left: 0, top: 0, width: 400, height: 600},
    1920, 1080, 200, 20), null); // Top letterbox.
  assert.equal(coords(rect, 0, 0, 500, 275), null);
  const edge = coords(rect, 1600, 900, 900, 500);
  assert.equal(edge.x, 1);
  assert.equal(edge.y, 1);

  const click = {button: 0, buttons: 1, pointerId: 1, isPrimary: true,
    clientX: 500, clientY: 275, preventDefault() {}};
  context.startPreviewGesture({...click, clientX: 110});
  context.startPreviewGesture({...click, button: 2});
  assert.equal(requests.length, 0);
  context.startPreviewGesture(click);
  // Fast press/release must preserve down/up order while down is in flight.
  context.endPreviewGesture(click);
  await settle();
  assert.deepEqual(phases(), ['down', 'up']);
  assert.equal(requests[0][0], '/api/screen-preview/pointer');
  assert.equal(requests[0][1].headers.Authorization, 'Bearer admin-token');
  const start = JSON.parse(requests[0][1].body);
  assert.equal(start.frameId, 'frame-1');
  assert.equal(start.x, 0.5);
  assert.equal(start.y, 0.5);
  assert.equal(capturedPointer, null);

  context.startPreviewGesture(click);
  await settle();
  context.movePreviewGesture({...click, clientX: 510});
  context.movePreviewGesture({...click, clientX: 550});
  const moveTimer = [...timers.entries()].find(([, timer]) => timer.ms === 50);
  timers.delete(moveTimer[0]);
  moveTimer[1].fn();
  await settle();
  context.endPreviewGesture({...click, clientX: 2000, clientY: 2000});
  await settle();
  assert.deepEqual(phases(), ['down', 'up', 'down', 'move', 'up']);
  const end = JSON.parse(requests.at(-1)[1].body);
  assert.equal(end.x, 1);
  assert.equal(end.y, 1);
  assert.equal(end.sequence, 3);
  assert.equal(timers.size, 0);

  context.startPreviewGesture(click);
  await settle();
  context.cancelPreviewGesture({pointerId: 2}); // Ignore another finger.
  await settle();
  assert.equal(phases().at(-1), 'down');
  context.cancelPreviewGesture();
  await settle();
  assert.equal(phases().at(-1), 'cancel');
  assert.equal(capturedPointer, null);
  assert.equal(timers.size, 0);
  const count = requests.length;
  context.previewActive = false;
  context.startPreviewGesture(click);
  context.previewActive = true;
  image.dataset.clickable = 'false';
  context.startPreviewGesture(click);
  image.dataset.clickable = 'true';
  context.document.hidden = true;
  context.startPreviewGesture(click);
  assert.equal(requests.length, count);
  assert.equal(notices.length, 0);
  console.log('Admin preview: click/drag ordering, move coalescing, cancellation and coordinate checks passed.');
}

module.exports = verify();
if (require.main === module) module.exports.catch(error => {
  console.error(error);
  process.exitCode = 1;
});
