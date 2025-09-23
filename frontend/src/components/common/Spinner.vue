<!-- filepath: c:\Users\Alejandro\Desktop\microservice-app-example\frontend\src\components\common\Spinner.vue -->
<template>
<div class="spinner-container">
  <div class="spinner-content">
    <div class="simple-spinner">Loading...</div>
    <br>
    <div class="spinner-message">{{ message }}</div>
  </div>
</div>
</template>

<script>
export default {
  name: 'spinner',
  props: {
    message: {
      type: String,
      default: 'Loading...'
    }
  }
}
</script>

<style scoped>
.spinner-container {
  position: fixed;
  top: 0;
  left: 0;
  width: 100%;
  height: 100%;
  background-color: rgba(255, 255, 255, 0.8);
  display: flex;
  justify-content: center;
  align-items: center;
  z-index: 9999;
}

.simple-spinner {
  font-size: 18px;
  font-weight: bold;
  color: #007bff;
}
</style>