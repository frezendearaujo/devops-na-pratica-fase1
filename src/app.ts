import express, { type Express } from 'express'

import { TaskRepository } from './task-repository.js'
import { TITLE_MAX_LENGTH } from './task.js'

type TitleValidation = { ok: true; title: string } | { ok: false; error: string }

function validateTitle(value: unknown): TitleValidation {
  if (value === undefined || value === null) {
    return { ok: false, error: 'title is required' }
  }

  if (typeof value !== 'string') {
    return { ok: false, error: 'title must be a string' }
  }

  const title = value.trim()

  if (title.length === 0) {
    return { ok: false, error: 'title is required' }
  }

  if (title.length > TITLE_MAX_LENGTH) {
    return { ok: false, error: `title must be at most ${TITLE_MAX_LENGTH} characters` }
  }

  return { ok: true, title }
}

export function createApp(repository: TaskRepository = new TaskRepository()): Express {
  const app = express()

  app.use(express.json())

  app.get('/health', (_req, res) => {
    res.status(200).json({ status: 'ok' })
  })

  app.get('/tasks', (_req, res) => {
    res.status(200).json(repository.list())
  })

  app.post('/tasks', (req, res) => {
    const validation = validateTitle(req.body?.title)

    if (!validation.ok) {
      res.status(400).json({ error: validation.error })
      return
    }

    res.status(201).json(repository.create(validation.title))
  })

  app.post('/tasks/:id/complete', (req, res) => {
    const task = repository.complete(req.params.id)

    if (!task) {
      res.status(404).json({ error: 'task not found' })
      return
    }

    res.status(200).json(task)
  })

  return app
}
