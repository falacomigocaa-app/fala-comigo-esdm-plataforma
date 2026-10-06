import test from 'node:test';
import assert from 'node:assert/strict';
import {
  buildReportPrintMetadata,
  exportClinicalReportPdf,
  filterReportData,
  renderReportChart,
  renderReportsView,
  summarizeReport
} from '../src/views/reports-view.js';
import { DECODE_ERROR_MESSAGE, decryptCollectionEnvelopes } from '../src/services/crypto-web.service.js';

const toBase64 = (bytes) => Buffer.from(bytes).toString('base64');

test('reports view renderiza filtros, estados e área SVG do compilado', () => {
  const html = renderReportsView({ session: { userId: 'user-professional-alpha' } });
  assert.match(html, /Relatórios de evolução/);
  assert.match(html, /data-report-period/);
  assert.match(html, /data-report-goal-filter/);
  assert.match(html, /data-report-chart/);
  assert.match(html, /data-print-report/);
  assert.match(html, /data-report-print-cover/);
  assert.match(html, /Baixar PDF/);
  assert.match(html, /data-report-chart/);
});

test('reports view filtra coletas por período e metas por código', () => {
  const now = new Date('2026-10-05T12:00:00.000Z');
  const result = filterReportData([
    { dataRegistro: '2026-10-04T12:00:00.000Z', nivelSuporte: 'Independente' },
    { dataRegistro: '2026-09-01T12:00:00.000Z', nivelSuporte: 'Recusa' }
  ], [
    { codigoTecnicoDenver: 'CE_N1_I5' },
    { codigoTecnicoDenver: 'SOC_N1_I3' }
  ], { period: '7', goalCode: 'CE_N1_I5', now });

  assert.equal(result.collections.length, 1);
  assert.equal(result.goals.length, 1);
  assert.equal(result.goals[0].codigoTecnicoDenver, 'CE_N1_I5');
});

test('reports view resume autonomia e último registro', () => {
  const summary = summarizeReport([
    { dataRegistro: '2026-10-01T12:00:00.000Z', nivelSuporte: 'Ajuda Verbal' },
    { dataRegistro: '2026-10-04T12:00:00.000Z', nivelSuporte: 'Independente' }
  ], [{ codigoTecnicoDenver: 'CE_N1_I5' }]);

  assert.equal(summary.collectionCount, 2);
  assert.equal(summary.average, 2.5);
  assert.equal(summary.goalCount, 1);
  assert.equal(summary.lastDate.toISOString(), '2026-10-04T12:00:00.000Z');
});

test('exportação mantém identidade do paciente, organização e filtros atuais', () => {
  const summary = summarizeReport([
    { dataRegistro: '2026-10-04T12:00:00.000Z', nivelSuporte: 'Independente' }
  ], [{ codigoTecnicoDenver: 'CE_N1_I5' }]);
  const metadata = buildReportPrintMetadata({
    patient: { id: 'subject-1', displayName: 'Lia Silva' },
    organization: 'Clínica Horizonte',
    periodLabel: 'Últimos 30 dias',
    goalLabel: 'CE_N1_I5',
    summary,
    emittedAt: new Date('2026-10-05T12:00:00.000Z')
  });

  assert.deepEqual({
    patientName: metadata.patientName,
    organizationName: metadata.organizationName,
    periodLabel: metadata.periodLabel,
    goalLabel: metadata.goalLabel,
    collectionCount: metadata.collectionCount,
    average: metadata.average,
    goalCount: metadata.goalCount
  }, {
    patientName: 'Lia Silva',
    organizationName: 'Clínica Horizonte',
    periodLabel: 'Últimos 30 dias',
    goalLabel: 'CE_N1_I5',
    collectionCount: 1,
    average: '3.0',
    goalCount: 1
  });
  assert.ok(metadata.issuedAt.length > 0);
});

test('exportação chama impressão apenas com sessão autenticada', () => {
  let printCalls = 0;
  const windowRef = { print: () => { printCalls += 1; } };
  assert.equal(exportClinicalReportPdf({ documentRef: {}, windowRef, session: { token: 'access' } }), true);
  assert.equal(printCalls, 1);
  assert.equal(exportClinicalReportPdf({ documentRef: {}, windowRef, session: null }), false);
  assert.equal(printCalls, 1);
});

test('descriptografa envelope AES-GCM da organização e renderiza o gráfico clínico', async () => {
  const cryptoRef = globalThis.crypto;
  const key = await cryptoRef.subtle.generateKey({ name: 'AES-GCM', length: 256 }, true, ['encrypt', 'decrypt']);
  const rawKey = new Uint8Array(await cryptoRef.subtle.exportKey('raw', key));
  const iv = cryptoRef.getRandomValues(new Uint8Array(12));
  const plaintext = JSON.stringify({
    dataRegistro: '2026-10-04T12:00:00.000Z',
    nivelSuporte: 'Independente'
  });
  const encrypted = new Uint8Array(await cryptoRef.subtle.encrypt({ name: 'AES-GCM', iv }, key, new TextEncoder().encode(plaintext)));
  const [collection] = await decryptCollectionEnvelopes([{
    organizationId: 'org-demo-alpha',
    encryptedData: toBase64(encrypted),
    iv: toBase64(iv)
  }], {
    session: { organizationId: 'org-demo-alpha', organizationKey: toBase64(rawKey) },
    cryptoRef
  });
  const chart = renderReportChart([collection]);
  assert.equal(collection.nivelSuporte, 'Independente');
  assert.match(chart, /<svg/);
  assert.match(chart, /Evolução da autonomia/);
});

test('chave E2EE ausente falha com mensagem amigável de decodificação', async () => {
  await assert.rejects(
    decryptCollectionEnvelopes([{
      organizationId: 'org-demo-alpha',
      encryptedData: 'AA==',
      iv: 'AAAAAAAAAAAAAAAA'
    }], { session: { organizationId: 'org-demo-alpha' } }),
    (error) => error.code === 'E2EE_KEY_INVALID' && error.message === DECODE_ERROR_MESSAGE
  );
});
