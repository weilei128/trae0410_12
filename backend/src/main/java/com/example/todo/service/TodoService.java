package com.example.todo.service;

import com.example.todo.model.Todo;
import org.springframework.stereotype.Service;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

@Service
public class TodoService {
    private static final String DATA_DIR = System.getenv().getOrDefault("DATA_DIR", System.getProperty("user.dir"));
    private static final String JSON_FILE_PATH = DATA_DIR + "/todo.json";

    public List<Todo> getAllTodos() {
        return readTodosFromFile();
    }

    public Todo getTodoById(Long id) {
        List<Todo> todos = readTodosFromFile();
        return todos.stream()
                .filter(todo -> todo.getId().equals(id))
                .findFirst()
                .orElse(null);
    }

    public Todo createTodo(Todo todo) {
        List<Todo> todos = readTodosFromFile();
        Long newId = generateNextId(todos);
        todo.setId(newId);
        todo.setCompleted(false);
        todos.add(todo);
        writeTodosToFile(todos);
        return todo;
    }

    public Todo updateTodo(Long id, Todo todoDetails) {
        List<Todo> todos = readTodosFromFile();
        Optional<Todo> optionalTodo = todos.stream()
                .filter(todo -> todo.getId().equals(id))
                .findFirst();
        
        if (optionalTodo.isPresent()) {
            Todo todo = optionalTodo.get();
            todo.setTitle(todoDetails.getTitle());
            todo.setCompleted(todoDetails.isCompleted());
            writeTodosToFile(todos);
            return todo;
        }
        return null;
    }

    public boolean deleteTodo(Long id) {
        List<Todo> todos = readTodosFromFile();
        boolean removed = todos.removeIf(todo -> todo.getId().equals(id));
        if (removed) {
            writeTodosToFile(todos);
        }
        return removed;
    }

    public Todo toggleTodo(Long id) {
        List<Todo> todos = readTodosFromFile();
        Optional<Todo> optionalTodo = todos.stream()
                .filter(todo -> todo.getId().equals(id))
                .findFirst();
        
        if (optionalTodo.isPresent()) {
            Todo todo = optionalTodo.get();
            todo.setCompleted(!todo.isCompleted());
            writeTodosToFile(todos);
            return todo;
        }
        return null;
    }

    private Long generateNextId(List<Todo> todos) {
        return todos.stream()
                .mapToLong(Todo::getId)
                .max()
                .orElse(0) + 1;
    }

    private File getDataFile() {
        File file = new File(JSON_FILE_PATH);
        if (!file.exists()) {
            try {
                file.createNewFile();
                try (OutputStreamWriter writer = new OutputStreamWriter(
                        new FileOutputStream(file), StandardCharsets.UTF_8)) {
                    writer.write("[]");
                }
            } catch (IOException e) {
                e.printStackTrace();
            }
        }
        return file;
    }

    private List<Todo> readTodosFromFile() {
        try {
            File file = getDataFile();
            BufferedReader reader = new BufferedReader(new InputStreamReader(
                    new FileInputStream(file), StandardCharsets.UTF_8));
            StringBuilder content = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) {
                content.append(line);
            }
            reader.close();
            
            String json = content.toString().trim();
            if (json.isEmpty() || json.equals("[]")) {
                return new ArrayList<>();
            }
            
            return parseJsonToTodos(json);
        } catch (IOException e) {
            return new ArrayList<>();
        }
    }

    private void writeTodosToFile(List<Todo> todos) {
        try {
            String json = convertTodosToJson(todos);
            File file = getDataFile();
            try (OutputStreamWriter writer = new OutputStreamWriter(
                    new FileOutputStream(file), StandardCharsets.UTF_8)) {
                writer.write(json);
            }
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    private List<Todo> parseJsonToTodos(String json) {
        List<Todo> todos = new ArrayList<>();
        json = json.trim();
        if (json.startsWith("[") && json.endsWith("]")) {
            json = json.substring(1, json.length() - 1).trim();
            if (json.isEmpty()) {
                return todos;
            }
            
            StringBuilder currentObj = new StringBuilder();
            int braceCount = 0;
            
            for (int i = 0; i < json.length(); i++) {
                char c = json.charAt(i);
                if (c == '{') {
                    braceCount++;
                    currentObj.append(c);
                } else if (c == '}') {
                    braceCount--;
                    currentObj.append(c);
                    if (braceCount == 0) {
                        Todo todo = parseTodoObject(currentObj.toString().trim());
                        if (todo != null) {
                            todos.add(todo);
                        }
                        currentObj = new StringBuilder();
                    }
                } else if (c == ',' && braceCount == 0) {
                    continue;
                } else {
                    currentObj.append(c);
                }
            }
        }
        return todos;
    }

    private Todo parseTodoObject(String obj) {
        obj = obj.trim();
        if (!obj.startsWith("{") || !obj.endsWith("}")) {
            return null;
        }
        
        obj = obj.substring(1, obj.length() - 1).trim();
        Long id = null;
        String title = null;
        boolean completed = false;
        
        String[] parts = obj.split(",");
        for (String part : parts) {
            part = part.trim();
            if (part.startsWith("\"id\"")) {
                id = Long.parseLong(extractValue(part));
            } else if (part.startsWith("\"title\"")) {
                title = extractStringValue(part);
            } else if (part.startsWith("\"completed\"")) {
                completed = Boolean.parseBoolean(extractValue(part));
            }
        }
        
        if (id != null && title != null) {
            return new Todo(id, title, completed);
        }
        return null;
    }

    private String extractValue(String part) {
        int colonIndex = part.indexOf(':');
        return part.substring(colonIndex + 1).trim();
    }

    private String extractStringValue(String part) {
        int colonIndex = part.indexOf(':');
        String value = part.substring(colonIndex + 1).trim();
        if (value.startsWith("\"") && value.endsWith("\"")) {
            return value.substring(1, value.length() - 1);
        }
        return value;
    }

    private String convertTodosToJson(List<Todo> todos) {
        StringBuilder json = new StringBuilder("[\n");
        for (int i = 0; i < todos.size(); i++) {
            Todo todo = todos.get(i);
            json.append("  {\"id\": ").append(todo.getId())
                .append(", \"title\": \"").append(escapeJson(todo.getTitle()))
                .append("\", \"completed\": ").append(todo.isCompleted()).append("}");
            if (i < todos.size() - 1) {
                json.append(",");
            }
            json.append("\n");
        }
        json.append("]");
        return json.toString();
    }

    private String escapeJson(String str) {
        return str.replace("\\", "\\\\")
                  .replace("\"", "\\\"")
                  .replace("\n", "\\n")
                  .replace("\r", "\\r")
                  .replace("\t", "\\t");
    }
}
