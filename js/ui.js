// ============================================================
// ui.js — отрисовка интерфейса
// ============================================================

const UI = {
    // Элементы
    el: {},

    init() {
        this.el = {
            onboarding: document.getElementById('onboarding'),
            dashboard: document.getElementById('dashboard'),
            walletStatus: document.getElementById('walletStatus'),
            connectBtn: document.getElementById('connectWalletBtn'),
            startBtn: document.getElementById('startBtn'),
            userGreeting: document.getElementById('userName'),
            userRating: document.getElementById('userRating'),
            activeAgreements: document.getElementById('activeAgreements'),
            searchInput: document.getElementById('searchInput'),
            searchBtn: document.getElementById('searchBtn'),
            searchResults: document.getElementById('searchResults'),
            daoVotes: document.getElementById('daoVotes'),
            createBtn: document.getElementById('createAgreementBtn'),
            modal: document.getElementById('agreementModal'),
            closeModalBtn: document.getElementById('closeModalBtn'),
            agreementForm: document.getElementById('agreementForm'),
        };
        this.bindEvents();
        this.render();
    },

    bindEvents() {
        this.el.connectBtn.addEventListener('click', () => this.handleConnect());
        this.el.startBtn.addEventListener('click', () => this.handleStart());
        this.el.createBtn.addEventListener('click', () => this.showModal());
        this.el.closeModalBtn.addEventListener('click', () => this.hideModal());
        this.el.modal.querySelector('.modal__overlay').addEventListener('click', () => this.hideModal());
        this.el.agreementForm.addEventListener('submit', (e) => this.handleCreateAgreement(e));
        this.el.searchBtn.addEventListener('click', () => this.handleSearch());
        this.el.searchInput.addEventListener('keyup', (e) => {
            if (e.key === 'Enter') this.handleSearch();
        });
    },

    // Подключение кошелька
    async handleConnect() {
        try {
            this.el.connectBtn.textContent = 'Подключение...';
            this.el.connectBtn.disabled = true;
            await Web3Adapter.connect();
            this.render();
            // Показываем дашборд
            this.el.onboarding.style.display = 'none';
            this.el.dashboard.style.display = 'block';
        } catch (err) {
            alert('Ошибка подключения: ' + err.message);
        } finally {
            this.el.connectBtn.textContent = 'Подключить кошелёк';
            this.el.connectBtn.disabled = false;
        }
    },

    // Кнопка "Начать" — переводим к подключению
    handleStart() {
        this.handleConnect();
    },

    // Рендеринг
    render() {
        const connected = Web3Adapter.isConnected;
        const address = Web3Adapter.getAddress();

        // Статус кошелька
        if (connected && address) {
            this.el.walletStatus.textContent = address.slice(0, 6) + '...' + address.slice(-4);
            this.el.userGreeting.textContent = 'Участник ' + address.slice(0, 6);
            // Рейтинг
            const stats = AgreementManager.getStats(address);
            this.el.userRating.textContent = '⭐ ' + stats.rating.toFixed(1) + ' (' + stats.total + ' обменов)';
        } else {
            this.el.walletStatus.textContent = 'Не подключён';
        }

        // Активные соглашения
        this.renderActiveAgreements();

        // DAO (имитация)
        this.renderDAO();

        // Если подключены — показываем дашборд
        if (connected) {
            this.el.onboarding.style.display = 'none';
            this.el.dashboard.style.display = 'block';
        }
    },

    // Активные соглашения
    renderActiveAgreements() {
        const active = AgreementManager.getActive();
        const container = this.el.activeAgreements;

        if (active.length === 0) {
            container.innerHTML = '<p class="empty-state">Нет активных соглашений</p>';
            return;
        }

        container.innerHTML = active.map(a => `
            <div class="agreement-card">
                <div class="agreement-card__info">
                    <span class="agreement-card__status status-${a.status}">${this.statusLabel(a.status)}</span>
                    <strong>${a.valueA}</strong>
                    <span style="color:var(--gray-dark);font-size:13px;">→ ${a.valueB}</span>
                    <span style="color:var(--gray-dark);font-size:13px;">📅 ${a.deadline} дн.</span>
                </div>
                <div class="agreement-card__actions">
                    ${a.status === 'active' ? `<button class="btn btn--small btn--primary" onclick="window.fulfillAgreement('${a.id}')">Исполнить</button>` : ''}
                    ${a.status === 'fulfilled' ? `<button class="btn btn--small btn--primary" onclick="window.confirmAgreement('${a.id}')">Подтвердить</button>` : ''}
                    <button class="btn btn--small btn--secondary" onclick="window.disputeAgreement('${a.id}')">⚠️ Спор</button>
                </div>
            </div>
        `).join('');
    },

    statusLabel(status) {
        const map = {
            active: '🟡 Активно',
            fulfilled: '🔵 Исполнено',
            completed: '🟢 Завершено',
            disputed: '🔴 Спор',
            cancelled: '⚪ Отменено',
        };
        return map[status] || status;
    },

    // DAO (имитация)
    renderDAO() {
        const container = this.el.daoVotes;
        const votes = [
            { id: 'P-001', title: 'Изменить комиссию до 0.7%', for: 68, against: 22, days: 3 },
            { id: 'P-002', title: 'Выбрать новых арбитров (5 мест)', for: 55, against: 30, days: 5 },
        ];
        container.innerHTML = votes.map(v => `
            <div class="dao-item">
                <span>${v.title}</span>
                <div class="dao-item__progress">
                    <span style="font-size:13px;">${v.for}%</span>
                    <div class="progress-bar">
                        <div class="progress-bar__fill" style="width:${v.for}%;"></div>
                    </div>
                    <span style="font-size:13px;color:var(--gray-dark);">${v.days} дн.</span>
                    <button class="btn btn--small btn--primary" onclick="alert('Голосование: ${v.id}')">Голосовать</button>
                </div>
            </div>
        `).join('');
    },

    // Поиск
    handleSearch() {
        const query = this.el.searchInput.value;
        const results = AgreementManager.search(query);
        const container = this.el.searchResults;

        if (results.length === 0) {
            container.innerHTML = '<p class="empty-state">Ничего не найдено</p>';
            return;
        }

        container.innerHTML = results.map(a => `
            <div class="agreement-card">
                <div class="agreement-card__info">
                    <span class="agreement-card__status status-${a.status}">${this.statusLabel(a.status)}</span>
                    <strong>${a.valueA}</strong>
                    <span style="color:var(--gray-dark);font-size:13px;">→ ${a.valueB}</span>
                </div>
            </div>
        `).join('');
    },

    // Модалка
    showModal() {
        if (!Web3Adapter.isConnected) {
            alert('Подключите кошелёк!');
            return;
        }
        this.el.modal.style.display = 'flex';
        document.body.style.overflow = 'hidden';
    },

    hideModal() {
        this.el.modal.style.display = 'none';
        document.body.style.overflow = '';
        this.el.agreementForm.reset();
    },

    // Создание соглашения
    async handleCreateAgreement(e) {
        e.preventDefault();

        const data = {
            valueA: document.getElementById('valueA').value.trim(),
            valueB: document.getElementById('valueB').value.trim(),
            amountB: document.getElementById('amountB').value,
            deadline: document.getElementById('deadline').value,
            description: document.getElementById('description').value.trim(),
            exchangeType: document.getElementById('exchangeType').value,
        };

        if (!data.valueA || !data.valueB) {
            alert('Заполните все поля!');
            return;
        }

        if (!document.getElementById('acceptHonor').checked) {
            alert('Примите Кодекс чести!');
            return;
        }

        try {
            const agreement = AgreementManager.create(data);
            alert('✅ Соглашение ' + agreement.id + ' создано!');
            this.hideModal();
            this.render();
        } catch (err) {
            alert('Ошибка: ' + err.message);
        }
    },

    // Действия с соглашениями (глобальные)
    fulfillAgreement(id) {
        if (confirm('Подтвердите исполнение ваших обязательств?')) {
            AgreementManager.fulfill(id);
            this.render();
        }
    },

    confirmAgreement(id) {
        if (confirm('Подтвердите получение?')) {
            AgreementManager.confirm(id);
            this.render();
        }
    },

    disputeAgreement(id) {
        const reason = prompt('Причина спора:');
        if (reason !== null) {
            AgreementManager.dispute(id, reason);
            this.render();
        }
    }
};

// Глобальные функции для onclick
window.fulfillAgreement = (id) => UI.fulfillAgreement(id);
window.confirmAgreement = (id) => UI.confirmAgreement(id);
window.disputeAgreement = (id) => UI.disputeAgreement(id);

window.UI = UI;
