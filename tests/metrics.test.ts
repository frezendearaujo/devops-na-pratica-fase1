import request from 'supertest'
import { beforeEach, describe, expect, it } from 'vitest'

import { createApp } from '../src/app.js'
import { TaskRepository } from '../src/task-repository.js'

describe('Endpoint de metricas', () => {
  let app: ReturnType<typeof createApp>

  beforeEach(() => {
    app = createApp(new TaskRepository())
  })

  it('GET /metrics responde 200 no formato de texto do Prometheus', async () => {
    const response = await request(app).get('/metrics')

    expect(response.status).toBe(200)
    expect(response.headers['content-type']).toContain('text/plain')
  })

  it('expoe as metricas padrao do processo', async () => {
    const response = await request(app).get('/metrics')

    expect(response.text).toContain('process_cpu_user_seconds_total')
    expect(response.text).toContain('nodejs_eventloop_lag_seconds')
  })

  it('contabiliza as requisicoes recebidas com metodo, rota e status', async () => {
    await request(app).get('/health')
    await request(app).get('/tasks')

    const response = await request(app).get('/metrics')

    expect(response.text).toContain('http_requests_total')
    expect(response.text).toMatch(/route="\/health".*status="200"/)
    expect(response.text).toMatch(/route="\/tasks".*status="200"/)
  })

  it('mede a duracao das requisicoes em um histograma', async () => {
    await request(app).post('/tasks').send({ title: 'medir a duracao' })

    const response = await request(app).get('/metrics')

    expect(response.text).toContain('http_request_duration_seconds_bucket')
    expect(response.text).toMatch(/route="\/tasks".*status="201"/)
  })

  it('aplica o rotulo de servico em todas as series', async () => {
    const response = await request(app).get('/metrics')

    expect(response.text).toContain('service="tasks-api"')
  })
})
