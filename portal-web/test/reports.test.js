import test from 'node:test';
import assert from 'node:assert/strict';
import { filterReportData, renderReportsView, summarizeReport } from '../src/views/reports-view.js';

test('reports view renderiza filtros, estados e área SVG do compilado', () => {
  const html = renderReportsView({ session: { userId: 'user-professional-alpha' } });
  assert.match(html, /Relatórios de evolução/);
  assert.match(html, /data-report-period/);
  assert.match(html, /data-report-goal-filter/);
  assert.match(html, /data-report-chart/);
  assert.match(html, /data-print-report/);
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
