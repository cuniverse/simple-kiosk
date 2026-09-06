// Run with: node test/admin_pc_shutdown_test.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const html = fs.readFileSync(path.join(__dirname, '../assets/admin/index.html'), 'utf8');
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];
new vm.Script(script);
const source = script.slice(script.indexOf('async function performAdminAction('),
  script.indexOf("document.querySelectorAll('[data-action]')"));
const requests = [], notices = [];
let approve = false, releaseRequest;
const context = vm.createContext({
  confirm: text => {assert.match(text, /PC.*종료/); return approve;},
  api: async (...args) => {requests.push(args); return {message: '접수'};},
  message: (...args) => notices.push(args),
  setTimeout: () => {}, previewActive: false,
});
vm.runInContext(source, context);
const button = {dataset: {action: 'shutdown-pc'}, textContent: 'PC 종료', disabled: false};

async function verify() {
  await context.performAdminAction(button);
  assert.equal(requests.length, 0); // Cancel never calls the API.
  approve = true;
  await context.performAdminAction(button);
  assert.equal(requests[0][0], '/api/actions/shutdown-pc');
  assert.deepEqual(JSON.parse(requests[0][1].body), {confirmed: true});
  assert.equal(button.disabled, false);

  context.api = () => new Promise(resolve => {releaseRequest = resolve;});
  const pending = context.performAdminAction(button);
  assert.equal(button.disabled, true);
  const completeRequest = releaseRequest;
  await context.performAdminAction(button);
  assert.equal(releaseRequest, completeRequest); // No second API request.
  completeRequest({message: '접수'});
  await pending;
  assert.equal(button.disabled, false);
  context.api = async () => {throw new Error('권한 없음');};
  await context.performAdminAction(button);
  assert.equal(button.disabled, false);
  assert.deepEqual(notices.at(-1), ['권한 없음', true]);
  console.log('PC shutdown confirmation, duplicate-click and error checks passed');
}
verify().catch(error => {console.error(error); process.exitCode = 1;});
