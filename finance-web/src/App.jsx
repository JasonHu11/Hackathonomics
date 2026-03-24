import { useEffect, useMemo, useRef, useState } from 'react'
import {
  CartesianGrid,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'

const LOAN_COLORS = ['#4bd1ff', '#57a6ff', '#67f39b', '#ec9bff', '#ffd166', '#ff7b7b']
const LOANS_STORAGE_KEY = 'finance-web-loans-v1'
const SPENDING_STORAGE_KEY = 'finance-web-spending-v1'
const INVESTING_STORAGE_KEY = 'finance-web-investing-v1'

function formatMoney(value) {
  return `$${Number(value).toLocaleString()}`
}

function minimumPayment(loan) {
  return loan.amount * (loan.interest / 100 / 12)
}

function cannotPayOff(loan) {
  return loan.monthlyPayment <= minimumPayment(loan)
}

function calculateMonthlyPayment(amount, annualRate, months) {
  if (amount <= 0 || months <= 0 || annualRate < 0) return null
  const monthlyRate = annualRate / 100 / 12
  if (monthlyRate === 0) return amount / months
  const denominator = 1 - Math.pow(1 + monthlyRate, -months)
  if (denominator <= 0) return null
  return (amount * monthlyRate) / denominator
}

function calculateMonthsFromPayment(amount, annualRate, payment) {
  if (amount <= 0 || payment <= 0 || annualRate < 0) return null
  const monthlyRate = annualRate / 100 / 12
  if (monthlyRate === 0) return amount / payment
  const minRequired = amount * monthlyRate
  if (payment <= minRequired) return null
  const months = -Math.log(1 - (amount * monthlyRate) / payment) / Math.log(1 + monthlyRate)
  if (!Number.isFinite(months) || months <= 0) return null
  return months
}

function payoffMonth(loan) {
  let balance = loan.amount
  const monthlyRate = loan.interest / 100 / 12
  const horizon = Math.max(1, Math.ceil(loan.termMonths || 360))

  for (let i = 1; i <= horizon; i += 1) {
    balance = balance * (1 + monthlyRate) - loan.monthlyPayment
    if (balance <= 0) return i
  }

  return null
}

function generateSpots(loan) {
  let balance = loan.amount
  const monthlyRate = loan.interest / 100 / 12
  const spots = [{ month: 0, balance: Number(balance.toFixed(2)) }]
  const horizon = Math.max(1, Math.ceil(loan.termMonths || 360))

  for (let i = 1; i <= horizon; i += 1) {
    balance = balance * (1 + monthlyRate) - loan.monthlyPayment
    if (balance <= 0) {
      spots.push({ month: i, balance: 0 })
      break
    }
    spots.push({ month: i, balance: Number(balance.toFixed(2)) })
  }

  return spots
}

function balanceAtMonth(loan, month) {
  const spots = generateSpots(loan)
  let last = spots[0]
  for (const s of spots) {
    if (s.month > month) break
    last = s
  }
  return last.balance
}

function xInterval(maxX) {
  const candidates = [6, 12, 18, 24, 36, 48, 60]
  return candidates.find((c) => maxX / c <= 8) ?? 60
}

function DashboardCard({ title, accent, metrics, onClick }) {
  return (
    <button className="dashboard-card glass-card" style={{ '--accent': accent }} onClick={onClick}>
      <div className="card-title">{title}</div>
      <div className="metrics-wrap">
        {Object.entries(metrics).map(([label, value]) => (
          <div key={label} className="metric-chip">
            <span className="metric-label">{label}</span>
            <span className="metric-value">{value}</span>
          </div>
        ))}
      </div>
    </button>
  )
}

function LoansPage({ onBack, loans, setLoans }) {
  const [form, setForm] = useState({
    name: '',
    amount: '',
    interest: '',
    payment: '',
    months: '',
  })
  const lastLoanFieldRef = useRef(null)
  const [showCombined, setShowCombined] = useState(true)
  const [message, setMessage] = useState('')

  const allGraphLoans = useMemo(
    () => loans.filter((loan) => loan.amount > 0 && loan.monthlyPayment > 0),
    [loans],
  )
  const chartLoans = useMemo(
    () =>
      loans.filter(
        (loan) => loan.amount > 0 && loan.monthlyPayment > 0 && loan.showOnChart !== false,
      ),
    [loans],
  )

  const maxX = useMemo(() => {
    if (allGraphLoans.length === 0) return 1
    return Math.max(
      ...allGraphLoans.map((loan) => {
        const spots = generateSpots(loan)
        return spots.at(-1)?.month ?? 1
      }),
      1,
    )
  }, [allGraphLoans])

  const chartRows = useMemo(() => {
    if (chartLoans.length === 0) return []
    const rows = []
    for (let m = 0; m <= maxX; m += 1) {
      const row = { month: m }
      chartLoans.forEach((loan) => {
        row[`loan_${loan.id}`] = Number(balanceAtMonth(loan, m).toFixed(2))
      })
      row.combinedAll = Number(
        allGraphLoans.reduce((sum, loan) => sum + balanceAtMonth(loan, m), 0).toFixed(2),
      )
      rows.push(row)
    }
    return rows
  }, [maxX, chartLoans, allGraphLoans])

  const maxY = useMemo(() => {
    if (chartRows.length === 0) return 100
    const peakBalances = chartRows.flatMap((row) =>
      chartLoans.map((loan) => Number(row[`loan_${loan.id}`] || 0)),
    )
    const combinedPeaks = showCombined ? chartRows.map((row) => Number(row.combinedAll || 0)) : []
    const rawMax = Math.max(...peakBalances, ...combinedPeaks, 100)
    return Math.ceil(rawMax * 1.1)
  }, [chartRows, chartLoans, showCombined])

  const updateForm = (field, value) => {
    setForm((prev) => {
      const next = { ...prev, [field]: value }
      if (field === 'payment') lastLoanFieldRef.current = 'payment'
      if (field === 'months') lastLoanFieldRef.current = 'months'

      const amount = Number(next.amount)
      const interest = Number(next.interest)
      const payment = Number(next.payment)
      const months = Number(next.months)

      if (amount > 0 && interest >= 0) {
        const drive = lastLoanFieldRef.current
        if (field === 'amount' || field === 'interest') {
          if (drive === 'months' && months > 0) {
            const computedPayment = calculateMonthlyPayment(amount, interest, months)
            if (computedPayment) next.payment = computedPayment.toFixed(2)
          } else if (drive === 'payment' && payment > 0) {
            const computedMonths = calculateMonthsFromPayment(amount, interest, payment)
            if (computedMonths) next.months = String(Math.ceil(computedMonths))
          } else if (payment > 0) {
            const computedMonths = calculateMonthsFromPayment(amount, interest, payment)
            if (computedMonths) next.months = String(Math.ceil(computedMonths))
          } else if (months > 0) {
            const computedPayment = calculateMonthlyPayment(amount, interest, months)
            if (computedPayment) next.payment = computedPayment.toFixed(2)
          }
        } else if (drive === 'months' && months > 0) {
          const computedPayment = calculateMonthlyPayment(amount, interest, months)
          if (computedPayment) next.payment = computedPayment.toFixed(2)
        } else if (drive === 'payment' && payment > 0) {
          const computedMonths = calculateMonthsFromPayment(amount, interest, payment)
          if (computedMonths) next.months = String(Math.ceil(computedMonths))
        }
      }
      return next
    })
  }

  const addLoan = () => {
    const amount = Number(form.amount)
    const interest = Number(form.interest)
    let monthlyPayment = Number(form.payment)
    let termMonths = Number(form.months)

    if (amount <= 0 || interest < 0) {
      setMessage('Please enter valid loan amount and interest rate.')
      return
    }
    if (termMonths <= 0 && monthlyPayment > 0) {
      const computedMonths = calculateMonthsFromPayment(amount, interest, monthlyPayment)
      termMonths = computedMonths ? Math.ceil(computedMonths) : 0
    }
    if (monthlyPayment <= 0 && termMonths > 0) {
      const computedPayment = calculateMonthlyPayment(amount, interest, termMonths)
      monthlyPayment = computedPayment ?? 0
    }
    if (monthlyPayment <= 0 || termMonths <= 0) {
      setMessage('Enter either valid monthly payment or valid number of months.')
      return
    }

    const loan = {
      id: Date.now(),
      name: form.name.trim() || `Loan ${loans.length + 1}`,
      amount,
      interest,
      monthlyPayment: Number(monthlyPayment.toFixed(2)),
      termMonths: Math.ceil(termMonths),
      showOnChart: true,
    }
    if (cannotPayOff(loan)) {
      setMessage(
        `Payment is too low. Minimum payment needed: ${formatMoney(minimumPayment(loan).toFixed(2))} / month.`,
      )
      return
    }

    setMessage('')
    setLoans((prev) => [...prev, loan])
    setForm({ name: '', amount: '', interest: '', payment: '', months: '' })
    lastLoanFieldRef.current = null
  }

  const removeLoan = (id) => setLoans((prev) => prev.filter((loan) => loan.id !== id))
  const toggleChartForLoan = (id) => {
    setLoans((prev) =>
      prev.map((loan) =>
        loan.id === id ? { ...loan, showOnChart: loan.showOnChart === false } : loan,
      ),
    )
  }

  return (
    <section>
      <button className="back-button ghost-btn" onClick={onBack}>
        ← Back
      </button>
      <h2 className="page-title">Loan Analyzer</h2>
      <div className="combined-toggle-row">
        <label className="chart-toggle-box">
          <input
            type="checkbox"
            checked={showCombined}
            onChange={(e) => setShowCombined(e.target.checked)}
          />
          Show combined graph (all loans)
        </label>
      </div>

      <div className="chart-shell glass-card">
        {allGraphLoans.length === 0 ? (
          <div className="empty-chart">Add a loan to see the chart</div>
        ) : (
          <ResponsiveContainer width="100%" height={280}>
            <LineChart data={chartRows} margin={{ top: 10, right: 10, left: 0, bottom: 5 }}>
              <CartesianGrid strokeDasharray="4 4" stroke="rgba(130, 164, 210, 0.18)" />
              <XAxis
                dataKey="month"
                type="number"
                domain={[0, maxX]}
                interval={0}
                stroke="#84a7d4"
                ticks={Array.from({ length: Math.floor(maxX / xInterval(maxX)) + 1 }, (_, i) => i * xInterval(maxX))}
              />
              <YAxis
                stroke="#84a7d4"
                domain={[0, maxY]}
                tickFormatter={(value) => (value >= 1000 ? `$${Math.round(value / 1000)}k` : `$${value}`)}
              />
              <Tooltip
                contentStyle={{
                  background: '#081a31',
                  border: '1px solid rgba(86, 140, 204, 0.5)',
                  borderRadius: 8,
                  color: '#dbe8ff',
                }}
                formatter={(value) => formatMoney(value)}
                labelFormatter={(label) => `Month ${label}`}
              />
              {showCombined && (
                <Line
                  type="monotone"
                  dataKey="combinedAll"
                  name="Combined (all loans)"
                  stroke="#ffffff"
                  strokeWidth={2}
                  dot={false}
                  strokeDasharray="6 4"
                  isAnimationActive={false}
                />
              )}
              {chartLoans.map((loan, i) => (
                <Line
                  key={loan.id}
                  type="monotone"
                  dataKey={`loan_${loan.id}`}
                  name={loan.name}
                  stroke={LOAN_COLORS[i % LOAN_COLORS.length]}
                  strokeWidth={3}
                  dot={false}
                  isAnimationActive={false}
                />
              ))}
            </LineChart>
          </ResponsiveContainer>
        )}
      </div>

      {loans.length > 0 && (
        <>
          <h3>Your Loans</h3>
          <div className="loan-list">
            {loans.map((loan, i) => {
              const bad = cannotPayOff(loan)
              const payoff = payoffMonth(loan)
              return (
                <article key={loan.id} className="loan-card glass-card">
                  <div
                    className="loan-swatch"
                    style={{ backgroundColor: bad ? '#7b8799' : LOAN_COLORS[i % LOAN_COLORS.length] }}
                  />
                  <div className="loan-main">
                    <div>
                      <div className="loan-name">{loan.name}</div>
                      <div className="loan-sub">
                        {formatMoney(loan.amount)} · {loan.interest}% APR · {formatMoney(loan.monthlyPayment)}/mo ·{' '}
                        {loan.termMonths} months
                      </div>
                    </div>
                    <div className="loan-actions">
                      <label className="chart-toggle-box">
                        <input
                          type="checkbox"
                          checked={loan.showOnChart !== false}
                          onChange={() => toggleChartForLoan(loan.id)}
                        />
                        Show graph
                      </label>
                      <button className="small-btn" onClick={() => removeLoan(loan.id)}>
                        Delete
                      </button>
                    </div>
                  </div>
                  <div className="loan-payoff">
                    Payoff: {payoff ? `${payoff} mo (${(payoff / 12).toFixed(1)} yr)` : 'Never'}
                  </div>
                  {bad && (
                    <div className="loan-warning">
                      Payment too low to cover interest. Minimum needed: {formatMoney(minimumPayment(loan).toFixed(2))}/mo
                    </div>
                  )}
                </article>
              )
            })}
          </div>
        </>
      )}

      <h3>Add Loan</h3>
      <div className="loan-form glass-card">
        <input
          value={form.name}
          placeholder="Loan Name (optional)"
          onChange={(e) => updateForm('name', e.target.value)}
        />
        <div className="grid2">
          <input
            value={form.amount}
            placeholder="Loan Amount"
            onChange={(e) => updateForm('amount', e.target.value)}
          />
          <input
            value={form.interest}
            placeholder="Interest Rate %"
            onChange={(e) => updateForm('interest', e.target.value)}
          />
        </div>
        <div className="grid2">
          <input
            value={form.payment}
            placeholder="Monthly Payment"
            onChange={(e) => updateForm('payment', e.target.value)}
          />
          <input
            value={form.months}
            placeholder="Number of Months"
            onChange={(e) => updateForm('months', e.target.value)}
          />
        </div>
        <button className="primary-btn neon-btn" onClick={addLoan}>
          Add Loan
        </button>
        {message ? <p className="form-message">{message}</p> : null}
      </div>
    </section>
  )
}

function SpendingPage({ onBack, spendingData, setSpendingData }) {
  const income = Number(spendingData.income || 0)
  const spend = Number(spendingData.spend || 0)
  const netIncome = income - spend

  return (
    <section>
      <button className="back-button ghost-btn" onClick={onBack}>
        ← Back
      </button>
      <h2 className="page-title">Cash Flow</h2>
      <div className="spending-grid">
        <div className="glass-card spending-big">
          <div className="panel-head">
            <strong>Net Income</strong>
            <span>VIEW MORE ↗</span>
          </div>
          <div className="money">{formatMoney(netIncome.toFixed(2))}</div>
          <div className="muted">Income - Spend</div>
        </div>
        <div className="glass-card panel">
          <div className="panel-head">
            <strong>Spend</strong>
            <span>VIEW MORE ↗</span>
          </div>
          <div className="money">{formatMoney(spend.toFixed(2))}</div>
          <div className="muted">Input spend amount</div>
          <input
            className="panel-input"
            value={spendingData.spend}
            placeholder="Spend"
            onChange={(e) =>
              setSpendingData((prev) => ({
                ...prev,
                spend: e.target.value,
              }))
            }
          />
          <div className="row">
            <span>Current</span>
            <strong>{formatMoney(spend.toFixed(2))}</strong>
          </div>
        </div>
        <div className="glass-card panel">
          <div className="panel-head">
            <strong>Income</strong>
            <span>VIEW MORE ↗</span>
          </div>
          <div className="money">{formatMoney(income.toFixed(2))}</div>
          <div className="muted">Input income amount</div>
          <input
            className="panel-input"
            value={spendingData.income}
            placeholder="Income"
            onChange={(e) =>
              setSpendingData((prev) => ({
                ...prev,
                income: e.target.value,
              }))
            }
          />
          <div className="row">
            <span>Net</span>
            <strong>{formatMoney(netIncome.toFixed(2))}</strong>
          </div>
        </div>
      </div>
    </section>
  )
}

function InvestingPage({ onBack, investingData, setInvestingData }) {
  return (
    <section>
      <button className="back-button ghost-btn" onClick={onBack}>
        ← Back
      </button>
      <h2 className="page-title">Investments</h2>
      <div className="glass-card investing-hero">
        <div className="muted">{investingData.ytdReturn || '0.00'}%</div>
        <div className="money large">{formatMoney(Number(investingData.portfolioValue || 0).toFixed(2))}</div>
        <div className="hero-label">total balance</div>
        <div className="investing-inputs">
          <input
            className="panel-input"
            value={investingData.portfolioValue}
            placeholder="Portfolio Value"
            onChange={(e) =>
              setInvestingData((prev) => ({
                ...prev,
                portfolioValue: e.target.value,
              }))
            }
          />
          <input
            className="panel-input"
            value={investingData.todayGain}
            placeholder="Today Gain"
            onChange={(e) =>
              setInvestingData((prev) => ({
                ...prev,
                todayGain: e.target.value,
              }))
            }
          />
          <input
            className="panel-input"
            value={investingData.ytdReturn}
            placeholder="YTD Return %"
            onChange={(e) =>
              setInvestingData((prev) => ({
                ...prev,
                ytdReturn: e.target.value,
              }))
            }
          />
        </div>
        <div className="range-tabs">
          {['1W', '1M', 'YTD', '3M', '1Y', 'ALL'].map((tab) => (
            <button key={tab} className={`tab-btn ${tab === '1M' ? 'active' : ''}`}>
              {tab}
            </button>
          ))}
        </div>
      </div>
      <div className="investing-list">
        <div className="glass-card list-row">
          <span>Accounts</span>
          <span>1M BALANCE CHANGE</span>
        </div>
        <div className="glass-card list-row">
          <span>Allocation</span>
          <span>BY PERCENTAGE</span>
        </div>
        <div className="glass-card list-row">
          <span>Holdings</span>
          <span>LAST PRICE</span>
        </div>
      </div>
    </section>
  )
}

function DashboardPage({ onNavigate, totalEarnings, cards }) {
  return (
    <section>
      <div className="earnings-card glass-card">
        <span>Total Earnings</span>
        <strong>${totalEarnings.toFixed(2)}</strong>
      </div>
      <div className="cards-list">
        {cards.map((card) => (
          <DashboardCard
            key={card.title}
            title={card.title}
            accent={card.accent}
            metrics={card.metrics}
            onClick={() => onNavigate(card.title.toLowerCase())}
          />
        ))}
      </div>
    </section>
  )
}

function App() {
  const [currentPage, setCurrentPage] = useState('dashboard')
  const [loans, setLoans] = useState(() => {
    if (typeof window === 'undefined') return []
    try {
      const saved = window.localStorage.getItem(LOANS_STORAGE_KEY)
      return saved ? JSON.parse(saved) : []
    } catch {
      return []
    }
  })
  const [spendingData, setSpendingData] = useState(() => {
    if (typeof window === 'undefined') return { income: '', spend: '' }
    try {
      const saved = window.localStorage.getItem(SPENDING_STORAGE_KEY)
      return saved ? JSON.parse(saved) : { income: '', spend: '' }
    } catch {
      return { income: '', spend: '' }
    }
  })
  const [investingData, setInvestingData] = useState(() => {
    if (typeof window === 'undefined') return { portfolioValue: '', todayGain: '', ytdReturn: '' }
    try {
      const saved = window.localStorage.getItem(INVESTING_STORAGE_KEY)
      return saved
        ? JSON.parse(saved)
        : { portfolioValue: '', todayGain: '', ytdReturn: '' }
    } catch {
      return { portfolioValue: '', todayGain: '', ytdReturn: '' }
    }
  })

  const spendingIncome = Number(spendingData.income || 0)
  const spendingSpend = Number(spendingData.spend || 0)
  const spendingNet = spendingIncome - spendingSpend
  const investingValue = Number(investingData.portfolioValue || 0)
  const totalLoanDue = loans.reduce((sum, loan) => sum + Number(loan.amount || 0), 0)
  const activeLoans = loans.length
  const chartVisibleLoans = loans.filter((loan) => loan.showOnChart !== false).length
  const totalEarnings = investingValue + spendingNet - totalLoanDue

  const cards = useMemo(
    () => [
      {
        title: 'Loans',
        accent: '#57a6ff',
        metrics: {
          'Active Loans': String(activeLoans),
          'Shown on Graph': String(chartVisibleLoans),
          'Total Due': formatMoney(totalLoanDue.toFixed(2)),
        },
      },
      {
        title: 'Investing',
        accent: '#4bd1ff',
        metrics: {
          'Portfolio Value': formatMoney(investingValue.toFixed(2)),
          'Today Gain': formatMoney(Number(investingData.todayGain || 0).toFixed(2)),
          'YTD Return': `${investingData.ytdReturn || 0}%`,
        },
      },
      {
        title: 'Spending',
        accent: '#67f39b',
        metrics: {
          Income: formatMoney(spendingIncome.toFixed(2)),
          Spend: formatMoney(spendingSpend.toFixed(2)),
          Net: formatMoney(spendingNet.toFixed(2)),
        },
      },
    ],
    [
      activeLoans,
      chartVisibleLoans,
      investingData.todayGain,
      investingData.ytdReturn,
      investingValue,
      spendingIncome,
      spendingNet,
      spendingSpend,
      totalLoanDue,
    ],
  )

  useEffect(() => {
    if (typeof window === 'undefined') return
    window.localStorage.setItem(LOANS_STORAGE_KEY, JSON.stringify(loans))
  }, [loans])

  useEffect(() => {
    if (typeof window === 'undefined') return
    window.localStorage.setItem(SPENDING_STORAGE_KEY, JSON.stringify(spendingData))
  }, [spendingData])

  useEffect(() => {
    if (typeof window === 'undefined') return
    window.localStorage.setItem(INVESTING_STORAGE_KEY, JSON.stringify(investingData))
  }, [investingData])

  const body = useMemo(() => {
    if (currentPage === 'loans') {
      return <LoansPage loans={loans} setLoans={setLoans} onBack={() => setCurrentPage('dashboard')} />
    }
    if (currentPage === 'investing') {
      return (
        <InvestingPage
          onBack={() => setCurrentPage('dashboard')}
          investingData={investingData}
          setInvestingData={setInvestingData}
        />
      )
    }
    if (currentPage === 'spending') {
      return (
        <SpendingPage
          onBack={() => setCurrentPage('dashboard')}
          spendingData={spendingData}
          setSpendingData={setSpendingData}
        />
      )
    }
    return <DashboardPage totalEarnings={totalEarnings} cards={cards} onNavigate={setCurrentPage} />
  }, [cards, currentPage, investingData, loans, spendingData, totalEarnings])

  return (
    <div className="app-shell">
      <header className="app-bar glass-card">
        <h1>Finance Dashboard</h1>
        <p className="muted">Pure web React version</p>
      </header>
      <main className="content">{body}</main>
    </div>
  )
}

export default App
