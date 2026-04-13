const { defineConfig } = require('@vue/cli-service')
module.exports = defineConfig({
  transpileDependencies: true,
  devServer: {
    port: 10012,
    proxy: {
      '/api': {
        target: 'http://localhost:10011',
        changeOrigin: true
      }
    }
  }
})
