// ============================================================
// web3.js — адаптер для подключения к блокчейну
// MVP использует имитацию (localStorage) для демонстрации
// ============================================================

const Web3Adapter = {
    // Состояние
    isConnected: false,
    address: null,
    chainId: null,

    // Инициализация
    init() {
        console.log('[Web3] Инициализация...');
        // Проверяем, есть ли сохранённый адрес
        const saved = localStorage.getItem('noking_wallet');
        if (saved) {
            this.address = saved;
            this.isConnected = true;
        }
        return this;
    },

    // Подключение кошелька
    async connect() {
        // В MVP — имитация подключения
        return new Promise((resolve) => {
            setTimeout(() => {
                this.address = '0x' + Array.from({ length: 40 }, () =>
                    '0123456789abcdef'[Math.floor(Math.random() * 16)]
                ).join('');
                this.isConnected = true;
                localStorage.setItem('noking_wallet', this.address);
                console.log('[Web3] Подключено:', this.address);
                resolve(this.address);
            }, 600);
        });
    },

    // Отключение
    disconnect() {
        this.isConnected = false;
        this.address = null;
        localStorage.removeItem('noking_wallet');
        console.log('[Web3] Отключено');
    },

    // Получить адрес
    getAddress() {
        return this.address;
    },

    // Подписать сообщение (имитация)
    async signMessage(message) {
        if (!this.isConnected) throw new Error('Кошелёк не подключён');
        console.log('[Web3] Подпись:', message);
        return '0x' + Array.from({ length: 64 }, () =>
            '0123456789abcdef'[Math.floor(Math.random() * 16)]
        ).join('');
    },

    // Отправить транзакцию (имитация)
    async sendTransaction(to, value, data) {
        if (!this.isConnected) throw new Error('Кошелёк не подключён');
        console.log('[Web3] Транзакция:', { to, value, data });
        return {
            hash: '0x' + Array.from({ length: 64 }, () =>
                '0123456789abcdef'[Math.floor(Math.random() * 16)]
            ).join(''),
            blockNumber: Math.floor(Math.random() * 1000000),
        };
    }
};

// Глобальный доступ
window.Web3Adapter = Web3Adapter;
