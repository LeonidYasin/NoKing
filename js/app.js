// ============================================================
// app.js — точка входа
// ============================================================

document.addEventListener('DOMContentLoaded', () => {
    // Инициализация Web3
    Web3Adapter.init();

    // Инициализация UI
    UI.init();

    // Если кошелёк уже подключён — показываем дашборд
    if (Web3Adapter.isConnected) {
        document.getElementById('onboarding').style.display = 'none';
        document.getElementById('dashboard').style.display = 'block';
        UI.render();
    }

    console.log('🚀 NoKing MVP запущен!');
});
