# Спецификация обмена NoKing (Exchange Protocol)

**Версия:** 1.0  
**Статус:** Черновик  
**Лицензия:** MIT

---

## 1. Введение

### 1.1. Назначение
Спецификация описывает протокол создания, исполнения и завершения двусторонних соглашений об обмене ценностями.
### 1.2. Участники
- **Party A** — сторона, которая передаёт ценность (товар, услугу, время, информацию, права, доступ, ресурс).
- **Party B** — сторона, которая получает ценность и передаёт что-то взамен (деньги, товар, услугу и т.д.).
- **Arbitrator** — независимый арбитр, назначенный для разрешения споров (из DAO).
- **Agreement** — смарт-контракт, описывающий условия обмена.
- **Agreement** — смарт-контракт, описывающий условия обмена.
### 1.3. Термины
| Термин | Описание |
|--------|----------|
| **Agreement** | Соглашение между Party A и Party B |
| **Value A** | Ценность, которую отдаёт Party A |
| **Value B** | Ценность, которую отдаёт Party B взамен |
| **Fulfillment** | Исполнение обязательств одной из сторон |
| **Confirmation** | Подтверждение получения ценностей |
| **Escrow** | Блокировка средств (если Value B — деньги) |
| **Dispute** | Спор о неисполнении условий |
| **Dispute** | Сп
| **Resolution** | Решение арбитра |

---

## 2. Жизненный цикл соглашения
┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐
│ Created │───►│ Active │───►│Completed │───►│ Done │
└──────────┘ └──────────┘ └──────────┘ └──────────┘
│ │ │
│ ▼ │
│ ┌──────────┐ │
└─────────►│Cancelled │◄────────┘
└──────────┘
│
▼
┌──────────┐ ┌──────────┐ ┌──────────┐
│ Disputed │───►│ Resolved │───►│ Done │
└──────────┘ └──────────┘ └──────────┘


### 2.1. Статусы
| Статус | Описание |
|--------|----------|
| `CREATED` | Соглашение создано, но не активировано |
| `ACTIVE` | Соглашение активно, стороны исполняют обязательства |Download
| `FULFILLED_A` | Party A исполнила свои обязательства |
| `CONFIRMED` | Party B подтвердила получение |
| `CANCELLED` | Соглашение отменено до исполнения |
| `CANCELLED` |
| `DISPUTED` | Инициирован спор |
| `RESOLVED` | Спор разрешён арбитром |
| `EXPIRED` | Срок истёк, соглашение закрыто автоматически |



## 3. Протокол создания соглашения

### 3.1. Структура соглашения


struct Agreement {
    bytes32 id;
    address partyB;           // Вторая сторона (получает и даёт взамен)
    address partyB;           // Вторая сторона (
    
    // Описание ценностей (IPFS-ссылки или структурированные данные)
    bytes valueA;             // Что отдаёт partyA (метаданные)
    bytes valueB;             // Что отдаёт partyB взамен
    
    uint256 amountB;          // Сумма в USDC (если valueB — деньги)
    uint256 deadline;         // Срок исполнения (timestamp)
    
    bytes evidenceA;          // Доказательства от partyA (IPFS-ссылка)
    bytes evidenceA;         
    bytes evidenceB;          // Доказательства от partyB
    
    Status status;
    bool fulfilledA;          // Party A исполнила?
    bool confirmedB;          // Party B подтвердила?
    
    // Арбитраж
    address arbitrator;       // Назначенный арбитр
    string disputeReason;
    bytes resolution;         // Решение арбитра
    
    uint256 createdAt;
    uint256 updatedAt;
}
3.2. Создание соглашения (Party A)
Функция:

function createAgreement(
    address _partyB,Download
    bytes calldata _valueB,
    uint256 _amountB,
    uint256 _deadline
) external returns (bytes32 agreementId)
) external returns (bytes32 agreementId)
Условия:

Party A — зарегистрированный участник.

Party B — зарегистрированный участник.

_deadline > block.timestamp + 3600 (минимум 1 час).

Если _amountB > 0, Party B должна внести сумму в эскроу при подтверждении.

Событие:

event AgreementCreated(
    bytes32 indexed agreementId,
    address indexed partyA,
    address indexed partyB,
    uint256 deadline
)
4. Протокол исполнения
4.1. Исполнение обязательств (Party A)
Функция:

function fulfillAgreement(
    bytes32 _agreementId,
    bytes calldata _evidence
) externalDownload
Условия:

Только Party A может исполнить.

Статус — ACTIVE.

Party A не исполнила ранее.

Party B не подтвердила ранее.

Результат:

Статус → FULFILLED_A.

Сохраняются доказательства.

Событие:


event AgreementFulfilled(Download
    bytes32 indexed agreementId,
    address indexed partyA,
    bytes evidence
)
4.2. Подтверждение получения (Party B)
Функция:


function confirmAgreement(
    bytes32 _agreementId
) externalDownload
Условия:

Только Party B может подтвердить.

Статус — FULFILLED_A (Party A уже исполнила).

Party B не подтверждала ранее.

Результат:

Статус → COMPLETED.

Если _amountB > 0 → Escrow разблокирует средства Party A.

Отзыв может быть оставлен в течение 7 дней.

Событие:

solidity
event AgreementConfirmed(
    bytes32 indexed agreementId,
    address indexed partyB
)
4.3. Автоматическое завершение (таймер)
Если Party B не подтверждает в течение _deadline + 48 часов:

Статус → COMPLETED (автоматически).

Средства разблокируются.

Party B получает предупреждение (нарушение кодекса).

5. Протокол отмены
5.1. Отмена до исполнения
Функция:

solidity
function cancelAgreement(
    bytes32 _agreementId
) externalDownload
Условия:

Только Party A или Party B.

Статус — CREATED или ACTIVE.

Никто не исполнил обязательства.

Средства не заблокированы.

Результат:

Статус → CANCELLED.

Сторона, инициировавшая отмену, получает штраф (если есть).

Событие:

solidity
event AgreementCancelled(
    bytes32 indexed agreementId,
    address indexed initiator
)Download
6. Протокол спора
6.1. Инициация спора
Функция:

solidity
function disputeAgreement(
    bytes32 _agreementId,
    string calldata _reason,
    bytes calldata _evidence
) external
Условия:

Только Party A или Party B.

Статус — ACTIVE или FULFILLED_A.

Нет завершённого или разрешённого спора.

Результат:

Статус → DISPUTED.

Средства замораживаются (если есть эскроу).

Система назначает арбитра (случайно из пула).

Арбитр уведомляется.

Событие:

solidity
event AgreementDisputed(
    bytes32 indexed agreementId,
    address indexed initiator,
    string reason,
    address arbitrator
)
6.2. Решение спора (арбитр)
Функция:

solidity
function resolveDispute(
    bytes32 _agreementId,
    uint8 _decision,
    bytes calldata _resolution
) external
Условия:

Только назначенный арбитр.

Статус — DISPUTED.

Решение принимается один раз.

Результат:

Статус → RESOLVED.

Escrow исполняет решение (выплата или возврат).

Решение фиксируется в блокчейне.

Варианты решения:

Код	Решение
1	В пользу Party A
2	В пользу Party B
3	Частичное удовлетворение
4	Отказ в удовлетворении
Событие:

solidity
event AgreementResolved(
    bytes32 indexed agreementId,
    uint8 decision,
    bytes resolution
)
6.3. Апелляция
Если сторона не согласна с решением:

Апелляция подаётся в течение 48 часов.

Апелляционный состав — 3 случайных арбитра.

Решение апелляции — окончательное.

7. Комиссии
7.1. Комиссия протокола
Фиксированная: 0.5–1% от суммы обмена.

Удерживается из эскроу.

Направляется в казну DAO.

7.2. Комиссия арбитра
1% от суммы обмена (при споре).

Выплачивается арбитру после разрешения.

Минимум $5.

8. Безопасность
8.1. Защита от повторного исполнения
Нельзя исполнить одно соглашение дважды.

Нельзя подтвердить одно соглашение дважды.

8.2. Защита от таймаутов
Таймер для автоматического завершения.

Защита от бесконечного ожидания подтверждения.

8.3. Защита от мошенничества
Доказательства — подписаны сторонами.

Отзывы — подписаны покупателем.

Арбитраж — публичен и прозрачен.

9. Примеры
9.1. Пример 1: Продажа товара
Соглашение:

Party A: Продавец (отдаёт iPhone)

Party B: Покупатель (даёт 500 USDC)

Срок: 7 дней

Доказательства: фото отправки (Party A), подтверждение получения (Party B)

Процесс:

Party A создаёт соглашение.

Party B вносит 500 USDC в эскроу.

Party A отправляет iPhone → отправляет доказательства.

Party B подтверждает получение → деньги разблокируются.

Готово.

9.2. Пример 2: Спор
Ситуация:

Party A отправил код, но Party B говорит, что код не работает.

Party A предоставляет логи работы кода.

Party B предоставляет скриншоты ошибок.

Процесс:

Party B инициирует спор.

Система назначает арбитра.

Арбитр изучает доказательства.

Решение: Party A должен исправить код в течение 3 дней.

Если Party A исправляет → Party B подтверждает → деньги выплачены.

Если нет → деньги возвращены Party B.

9.3. Пример 3: Услуги фрилансера
Соглашение:

Party A: Фрилансер (делает дизайн)

Party B: Клиент (платит 200 USDC)

Срок: 5 дней

Этапы: 50% аванс + результат + оставшиеся 50%

Процесс:

Party A создаёт соглашение (этап 1: аванс 50%).

Party B вносит 100 USDC в эскроу.

Party A выполняет работу → Party B подтверждает → 100 USDC выплачены.

Party A создаёт соглашение (этап 2: финал 50%).

Party B вносит 100 USDC → Party A сдаёт финал → подтверждение → выплата.

Готово.

10. Интерфейсы (ABI)
10.1. Exchange.sol (псевдокод)
solidity
interface IExchange {
    function createAgreement(
        address partyB,
        bytes calldata valueA,
        bytes calldata valueB,
        uint256 amountB,
        uint256 deadline
    ) external returns (bytes32);
    
    function fulfillAgreement(
        bytes32 agreementId,
        bytes calldata evidence
    ) external;
    
    function confirmAgreement(
        bytes32 agreementId
    ) external;
    
    function cancelAgreement(
        bytes32 agreementId
    ) external;
    
    function disputeAgreement(
        bytes32 agreementId,
        string calldata reason,
        bytes calldata evidence
    ) external;
    
    function resolveDispute(
        bytes32 agreementId,
        uint8 decision,
        bytes calldata resolution
    ) external;
    
    function getAgreement(
        bytes32 agreementId
    ) external view returns (Agreement memory);
    
    event AgreementCreated(bytes32 indexed id, address indexed partyA, address indexed partyB);
    event AgreementFulfilled(bytes32 indexed id, address indexed partyA);
    event AgreementConfirmed(bytes32 indexed id, address indexed partyB);
    event AgreementCancelled(bytes32 indexed id, address indexed initiator);
    event AgreementDisputed(bytes32 indexed id, address indexed initiator, address arbitrator);
    event AgreementResolved(bytes32 indexed id, uint8 decision);
    }
12. Версионирование
Версия протокола: 1.0

Миграции: через голосование DAO.

Обратная совместимость: гарантируется для старых соглашений.

12. Лицензия
MIT — открыто для всех, навсегда.
