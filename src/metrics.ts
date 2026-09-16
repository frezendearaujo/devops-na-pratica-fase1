import type { NextFunction, Request, Response } from 'express'
import { Counter, Histogram, Registry, collectDefaultMetrics } from 'prom-client'

/**
 * Instrumentacao da aplicacao no formato do Prometheus.
 *
 * Cada instancia do app recebe um registry proprio, para que os testes nao
 * compartilhem estado e para que o container continue stateless.
 */
export interface Metrics {
  registry: Registry
  middleware: (req: Request, res: Response, next: NextFunction) => void
}

const DURATION_BUCKETS = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5]

export function createMetrics(): Metrics {
  const registry = new Registry()

  registry.setDefaultLabels({ service: 'tasks-api' })
  collectDefaultMetrics({ register: registry })

  const requestsTotal = new Counter({
    name: 'http_requests_total',
    help: 'Total de requisicoes HTTP recebidas.',
    labelNames: ['method', 'route', 'status'] as const,
    registers: [registry],
  })

  const requestDuration = new Histogram({
    name: 'http_request_duration_seconds',
    help: 'Duracao das requisicoes HTTP em segundos.',
    labelNames: ['method', 'route', 'status'] as const,
    buckets: DURATION_BUCKETS,
    registers: [registry],
  })

  function middleware(req: Request, res: Response, next: NextFunction): void {
    const stop = requestDuration.startTimer()

    res.on('finish', () => {
      // route.path so existe depois que o Express resolve a rota; sem ela, o
      // caminho cru entraria como label e explodiria a cardinalidade.
      const route = req.route?.path ?? req.path
      const labels = {
        method: req.method,
        route: typeof route === 'string' ? route : req.path,
        status: String(res.statusCode),
      }

      requestsTotal.inc(labels)
      stop(labels)
    })

    next()
  }

  return { registry, middleware }
}
