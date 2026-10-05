import { createStore } from '../src/store.js';

function fail(message, error = null) {
  console.error(`[test:db] FALHA: ${message}`);
  if (error) console.error(`[test:db] detalhe: ${error.message}`);
  return 1;
}

async function main() {
  if (!process.env.DATABASE_URL) {
    return fail('DATABASE_URL não foi definida. Configure o ambiente antes de executar npm run test:db.');
  }

  let store;
  try {
    store = createStore();
    if (!store.pool) throw new Error('O store não inicializou um Pool PostgreSQL.');

    const result = await store.pool.query('select 1 + 1 as result');
    const value = Number(result.rows[0]?.result);
    if (value !== 2) throw new Error(`Resultado inesperado da consulta: ${result.rows[0]?.result}`);

    console.log(`[test:db] SUCESSO: PostgreSQL respondeu SELECT 1 + 1 = ${value}.`);
    console.log(`[test:db] Pool inicializado em modo: ${store.storageMode}.`);
    return 0;
  } catch (error) {
    return fail('não foi possível conectar ou consultar o PostgreSQL. Verifique DATABASE_URL, credenciais, rede, certificado SSL e migration.', error);
  } finally {
    await store?.pool?.end().catch((error) => {
      console.error(`[test:db] aviso ao fechar o Pool: ${error.message}`);
    });
  }
}

const exitCode = await main();
process.exit(exitCode === 0 ? 0 : 1);
