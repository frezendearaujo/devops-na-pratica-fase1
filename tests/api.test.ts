import request from 'supertest'
import { beforeEach, describe, expect, it } from 'vitest'

import { createApp } from '../src/app.js'
import { TaskRepository } from '../src/task-repository.js'

describe('API de tarefas', () => {
  let app: ReturnType<typeof createApp>

  beforeEach(() => {
    app = createApp(new TaskRepository())
  })

  describe('caminhos felizes', () => {
    it('GET /health responde 200 com status ok', async () => {
      const response = await request(app).get('/health')

      expect(response.status).toBe(200)
      expect(response.body).toEqual({ status: 'ok' })
    })

    it('GET /tasks responde 200 com lista vazia', async () => {
      const response = await request(app).get('/tasks')

      expect(response.status).toBe(200)
      expect(response.body).toEqual([])
    })

    it('POST /tasks responde 201 com a tarefa criada', async () => {
      const response = await request(app).post('/tasks').send({ title: 'escrever os testes' })

      expect(response.status).toBe(201)
      expect(response.body).toMatchObject({
        title: 'escrever os testes',
        status: 'pending',
      })
      expect(response.body.id).toBeTypeOf('string')
      expect(response.body.createdAt).toBeTypeOf('string')
    })

    it('GET /tasks devolve as tarefas criadas', async () => {
      await request(app).post('/tasks').send({ title: 'primeira' })
      await request(app).post('/tasks').send({ title: 'segunda' })

      const response = await request(app).get('/tasks')

      expect(response.status).toBe(200)
      expect(response.body).toHaveLength(2)
      expect(response.body.map((task: { title: string }) => task.title)).toEqual([
        'primeira',
        'segunda',
      ])
    })

    it('POST /tasks/:id/complete responde 200 com status done', async () => {
      const created = await request(app).post('/tasks').send({ title: 'concluir a fase 1' })

      const response = await request(app).post(`/tasks/${created.body.id}/complete`)

      expect(response.status).toBe(200)
      expect(response.body).toMatchObject({ id: created.body.id, status: 'done' })
    })

    it('remove espacos em branco das bordas do titulo', async () => {
      const response = await request(app).post('/tasks').send({ title: '  com espacos  ' })

      expect(response.status).toBe(201)
      expect(response.body.title).toBe('com espacos')
    })
  })

  describe('erros', () => {
    it('POST /tasks sem titulo responde 400', async () => {
      const response = await request(app).post('/tasks').send({})

      expect(response.status).toBe(400)
      expect(response.body).toEqual({ error: 'title is required' })
    })

    it('POST /tasks com titulo vazio responde 400', async () => {
      const response = await request(app).post('/tasks').send({ title: '' })

      expect(response.status).toBe(400)
      expect(response.body).toEqual({ error: 'title is required' })
    })

    it('POST /tasks com titulo apenas de espacos responde 400', async () => {
      const response = await request(app).post('/tasks').send({ title: '   ' })

      expect(response.status).toBe(400)
      expect(response.body).toEqual({ error: 'title is required' })
    })

    it('POST /tasks com titulo que nao e string responde 400', async () => {
      const response = await request(app).post('/tasks').send({ title: 42 })

      expect(response.status).toBe(400)
      expect(response.body).toEqual({ error: 'title must be a string' })
    })

    it('POST /tasks com titulo acima de 120 caracteres responde 400', async () => {
      const response = await request(app)
        .post('/tasks')
        .send({ title: 'x'.repeat(121) })

      expect(response.status).toBe(400)
      expect(response.body).toEqual({
        error: 'title must be at most 120 characters',
      })
    })

    it('POST /tasks/:id/complete com id inexistente responde 404', async () => {
      const response = await request(app).post('/tasks/id-que-nao-existe/complete')

      expect(response.status).toBe(404)
      expect(response.body).toEqual({ error: 'task not found' })
    })
  })
})
