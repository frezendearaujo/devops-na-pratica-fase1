import { beforeEach, describe, expect, it } from 'vitest'

import { TaskRepository } from '../src/task-repository.js'

describe('TaskRepository', () => {
  let repository: TaskRepository

  beforeEach(() => {
    repository = new TaskRepository()
  })

  it('comeca vazio', () => {
    expect(repository.list()).toEqual([])
  })

  it('cria a tarefa com id, status pendente e createdAt em ISO 8601', () => {
    const task = repository.create('estudar terraform')

    expect(task.id).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/)
    expect(task.title).toBe('estudar terraform')
    expect(task.status).toBe('pending')
    expect(new Date(task.createdAt).toISOString()).toBe(task.createdAt)
  })

  it('gera um id diferente para cada tarefa', () => {
    const first = repository.create('primeira')
    const second = repository.create('segunda')

    expect(first.id).not.toBe(second.id)
  })

  it('lista as tarefas na ordem de criacao', () => {
    repository.create('primeira')
    repository.create('segunda')
    repository.create('terceira')

    expect(repository.list().map((task) => task.title)).toEqual(['primeira', 'segunda', 'terceira'])
  })

  it('conclui a tarefa alterando o status para done', () => {
    const created = repository.create('configurar o pipeline')

    const completed = repository.complete(created.id)

    expect(completed?.status).toBe('done')
    expect(repository.list()[0].status).toBe('done')
  })

  it('devolve null ao concluir uma tarefa inexistente', () => {
    expect(repository.complete('id-que-nao-existe')).toBeNull()
  })

  it('e idempotente ao concluir a mesma tarefa duas vezes', () => {
    const created = repository.create('revisar o documento')

    const first = repository.complete(created.id)
    const second = repository.complete(created.id)

    expect(second).toEqual(first)
    expect(repository.list()).toHaveLength(1)
  })
})
