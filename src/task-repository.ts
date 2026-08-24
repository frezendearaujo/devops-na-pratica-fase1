import { randomUUID } from 'node:crypto'

import type { Task } from './task.js'

/**
 * Armazenamento em memoria das tarefas.
 *
 * O estado vive no processo: cada instancia comeca vazia, o que mantem os testes
 * isolados e o container stateless.
 */
export class TaskRepository {
  private readonly tasks = new Map<string, Task>()

  list(): Task[] {
    return [...this.tasks.values()]
  }

  create(title: string): Task {
    const task: Task = {
      id: randomUUID(),
      title,
      status: 'pending',
      createdAt: new Date().toISOString(),
    }

    this.tasks.set(task.id, task)

    return task
  }

  complete(id: string): Task | null {
    const task = this.tasks.get(id)

    if (!task) {
      return null
    }

    const completed: Task = { ...task, status: 'done' }
    this.tasks.set(id, completed)

    return completed
  }
}
