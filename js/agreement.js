// ============================================================
// agreement.js — работа с соглашениями (имитация)
// ============================================================

const AgreementManager = {
    // Хранилище (localStorage)
    _getAgreements() {
        const data = localStorage.getItem('noking_agreements');
        return data ? JSON.parse(data) : [];
    },

    _saveAgreements(agreements) {
        localStorage.setItem('noking_agreements', JSON.stringify(agreements));
    },

    // Создать соглашение
    create(agreement) {
        const agreements = this._getAgreements();
        const newAgreement = {
            id: 'NK-' + Date.now().toString(36).toUpperCase(),
            createdAt: new Date().toISOString(),
            status: 'active', // active | fulfilled | completed | disputed | cancelled
            partyA: Web3Adapter.getAddress() || '0x...',
            partyB: null, // будет назначен позже
            ...agreement,
            amountB: parseFloat(agreement.amountB) || 0,
            deadline: parseInt(agreement.deadline) || 7,
        };
        agreements.unshift(newAgreement);
        this._saveAgreements(agreements);
        return newAgreement;
    },

    // Получить все соглашения
    getAll() {
        return this._getAgreements();
    },

    // Получить активные
    getActive() {
        return this._getAgreements().filter(a => a.status === 'active' || a.status === 'fulfilled');
    },

    // Получить по ID
    getById(id) {
        return this._getAgreements().find(a => a.id === id) || null;
    },

    // Обновить статус
    updateStatus(id, status, data = {}) {
        const agreements = this._getAgreements();
        const idx = agreements.findIndex(a => a.id === id);
        if (idx === -1) return null;
        agreements[idx].status = status;
        agreements[idx].updatedAt = new Date().toISOString();
        Object.assign(agreements[idx], data);
        this._saveAgreements(agreements);
        return agreements[idx];
    },

    // Подтвердить исполнение (со стороны Party A)
    fulfill(id) {
        return this.updateStatus(id, 'fulfilled', { fulfilledAt: new Date().toISOString() });
    },

    // Подтвердить получение (со стороны Party B)
    confirm(id) {
        return this.updateStatus(id, 'completed', { confirmedAt: new Date().toISOString() });
    },

    // Инициировать спор
    dispute(id, reason) {
        return this.updateStatus(id, 'disputed', { disputeReason: reason, disputedAt: new Date().toISOString() });
    },

    // Отменить
    cancel(id) {
        return this.updateStatus(id, 'cancelled', { cancelledAt: new Date().toISOString() });
    },

    // Поиск
    search(query) {
        const q = query.toLowerCase().trim();
        if (!q) return this.getAll();
        return this._getAgreements().filter(a =>
            a.valueA?.toLowerCase().includes(q) ||
            a.valueB?.toLowerCase().includes(q) ||
            a.description?.toLowerCase().includes(q)
        );
    },

    // Получить статистику для профиля
    getStats(address) {
        const all = this._getAgreements();
        const userAgreements = all.filter(a => a.partyA === address || a.partyB === address);
        return {
            total: userAgreements.length,
            active: userAgreements.filter(a => a.status === 'active' || a.status === 'fulfilled').length,
            completed: userAgreements.filter(a => a.status === 'completed').length,
            disputed: userAgreements.filter(a => a.status === 'disputed').length,
            rating: 4.7 + (Math.random() * 0.3 - 0.15), // имитация
        };
    }
};

window.AgreementManager = AgreementManager;
