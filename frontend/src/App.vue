<template>
  <div id="app">
    <div class="container">
      <h1>待办事项</h1>
      <div class="input-group">
        <input
          v-model="newTodo"
          @keyup.enter="addTodo"
          placeholder="请输入待办事项"
          type="text"
        />
        <button @click="addTodo" class="add-btn">添加</button>
      </div>
      <ul class="todo-list">
        <li v-for="todo in todos" :key="todo.id" class="todo-item">
          <span
            @click="toggleTodo(todo)"
            :class="{ completed: todo.completed }"
            class="todo-text"
          >
            {{ todo.title }}
          </span>
          <button @click="deleteTodo(todo.id)" class="delete-btn">删除</button>
        </li>
      </ul>
      <p v-if="todos.length === 0" class="empty-msg">暂无待办事项</p>
    </div>
  </div>
</template>

<script>
import axios from 'axios'

export default {
  name: 'App',
  data() {
    return {
      todos: [],
      newTodo: ''
    }
  },
  mounted() {
    this.fetchTodos()
  },
  methods: {
    async fetchTodos() {
      try {
        const response = await axios.get('/api/todos')
        this.todos = response.data
      } catch (error) {
        console.error('获取待办事项失败:', error)
      }
    },
    async addTodo() {
      if (!this.newTodo.trim()) return
      try {
        await axios.post('/api/todos', {
          title: this.newTodo.trim()
        })
        this.newTodo = ''
        this.fetchTodos()
      } catch (error) {
        console.error('添加待办事项失败:', error)
      }
    },
    async toggleTodo(todo) {
      try {
        await axios.put(`/api/todos/${todo.id}/toggle`)
        this.fetchTodos()
      } catch (error) {
        console.error('切换状态失败:', error)
      }
    },
    async deleteTodo(id) {
      try {
        await axios.delete(`/api/todos/${id}`)
        this.fetchTodos()
      } catch (error) {
        console.error('删除待办事项失败:', error)
      }
    }
  }
}
</script>

<style>
* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  min-height: 100vh;
  padding: 40px 20px;
}

#app {
  max-width: 600px;
  margin: 0 auto;
}

.container {
  background: white;
  border-radius: 16px;
  padding: 30px;
  box-shadow: 0 10px 40px rgba(0, 0, 0, 0.2);
}

h1 {
  text-align: center;
  color: #333;
  margin-bottom: 30px;
  font-size: 28px;
}

.input-group {
  display: flex;
  gap: 10px;
  margin-bottom: 20px;
}

.input-group input {
  flex: 1;
  padding: 12px 16px;
  border: 2px solid #e0e0e0;
  border-radius: 8px;
  font-size: 16px;
  transition: border-color 0.3s;
}

.input-group input:focus {
  outline: none;
  border-color: #667eea;
}

.add-btn {
  padding: 12px 24px;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  color: white;
  border: none;
  border-radius: 8px;
  font-size: 16px;
  cursor: pointer;
  transition: transform 0.2s, box-shadow 0.2s;
}

.add-btn:hover {
  transform: translateY(-2px);
  box-shadow: 0 4px 12px rgba(102, 126, 234, 0.4);
}

.todo-list {
  list-style: none;
}

.todo-item {
  display: flex;
  align-items: center;
  padding: 14px;
  border-bottom: 1px solid #f0f0f0;
  transition: background-color 0.2s;
}

.todo-item:hover {
  background-color: #f9f9f9;
}

.todo-text {
  flex: 1;
  cursor: pointer;
  font-size: 16px;
  color: #333;
  transition: color 0.3s;
}

.todo-text.completed {
  text-decoration: line-through;
  color: #999;
}

.delete-btn {
  padding: 6px 14px;
  background: #ff6b6b;
  color: white;
  border: none;
  border-radius: 6px;
  font-size: 14px;
  cursor: pointer;
  transition: background-color 0.2s;
}

.delete-btn:hover {
  background: #ee5a5a;
}

.empty-msg {
  text-align: center;
  color: #999;
  padding: 30px;
  font-size: 16px;
}
</style>
