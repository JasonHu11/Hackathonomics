import 'dart:convert';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const ConvertedApp());
}

enum AppPage { dashboard, loans, investing, spending }

class Loan {
  Loan({
    required this.id,
    required this.name,
    required this.amount,
    required this.interest,
    required this.monthlyPayment,
    required this.termMonths,
    this.showOnChart = true,
  });

  final String id;
  final String name;
  final double amount;
  final double interest;
  final double monthlyPayment;
  final int termMonths;
  final bool showOnChart;

  Loan copyWith({
    String? id,
    String? name,
    double? amount,
    double? interest,
    double? monthlyPayment,
    int? termMonths,
    bool? showOnChart,
  }) {
    return Loan(
      id: id ?? this.id,
      name: name ?? this.name,
      amount: amount ?? this.amount,
      interest: interest ?? this.interest,
      monthlyPayment: monthlyPayment ?? this.monthlyPayment,
      termMonths: termMonths ?? this.termMonths,
      showOnChart: showOnChart ?? this.showOnChart,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'amount': amount,
        'interest': interest,
        'monthlyPayment': monthlyPayment,
        'termMonths': termMonths,
        'showOnChart': showOnChart,
      };

  factory Loan.fromJson(Map<String, dynamic> json) => Loan(
        id: (json['id'] ?? '') as String,
        name: (json['name'] ?? 'Loan') as String,
        amount: (json['amount'] ?? 0).toDouble(),
        interest: (json['interest'] ?? 0).toDouble(),
        monthlyPayment: (json['monthlyPayment'] ?? 0).toDouble(),
        termMonths: (json['termMonths'] ?? 1) as int,
        showOnChart: (json['showOnChart'] ?? true) as bool,
      );
}

class SpendingData {
  SpendingData({this.income = '', this.spend = ''});

  final String income;
  final String spend;

  SpendingData copyWith({String? income, String? spend}) =>
      SpendingData(income: income ?? this.income, spend: spend ?? this.spend);

  Map<String, dynamic> toJson() => {'income': income, 'spend': spend};

  factory SpendingData.fromJson(Map<String, dynamic> json) => SpendingData(
        income: (json['income'] ?? '') as String,
        spend: (json['spend'] ?? '') as String,
      );
}

class InvestingData {
  InvestingData({
    this.portfolioValue = '',
    this.todayGain = '',
    this.ytdReturn = '',
  });

  final String portfolioValue;
  final String todayGain;
  final String ytdReturn;

  InvestingData copyWith({
    String? portfolioValue,
    String? todayGain,
    String? ytdReturn,
  }) {
    return InvestingData(
      portfolioValue: portfolioValue ?? this.portfolioValue,
      todayGain: todayGain ?? this.todayGain,
      ytdReturn: ytdReturn ?? this.ytdReturn,
    );
  }

  Map<String, dynamic> toJson() => {
        'portfolioValue': portfolioValue,
        'todayGain': todayGain,
        'ytdReturn': ytdReturn,
      };

  factory InvestingData.fromJson(Map<String, dynamic> json) => InvestingData(
        portfolioValue: (json['portfolioValue'] ?? '') as String,
        todayGain: (json['todayGain'] ?? '') as String,
        ytdReturn: (json['ytdReturn'] ?? '') as String,
      );
}

const loanColors = [
  Color(0xFF4BD1FF),
  Color(0xFF57A6FF),
  Color(0xFF67F39B),
  Color(0xFFEC9BFF),
  Color(0xFFFFD166),
  Color(0xFFFF7B7B),
];

double minimumPayment(Loan loan) {
  return loan.amount * (loan.interest / 100 / 12);
}

bool cannotPayOff(Loan loan) {
  return loan.monthlyPayment <= minimumPayment(loan);
}

double? calculateMonthlyPayment(double amount, double annualRate, double months) {
  if (amount <= 0 || months <= 0 || annualRate < 0) return null;
  final monthlyRate = annualRate / 100 / 12;
  if (monthlyRate == 0) return amount / months;
  final denominator = 1 - math.pow(1 + monthlyRate, -months);
  if (denominator <= 0) return null;
  return (amount * monthlyRate) / denominator;
}

double? calculateMonthsFromPayment(
  double amount,
  double annualRate,
  double payment,
) {
  if (amount <= 0 || payment <= 0 || annualRate < 0) return null;
  final monthlyRate = annualRate / 100 / 12;
  if (monthlyRate == 0) return amount / payment;
  final minRequired = amount * monthlyRate;
  if (payment <= minRequired) return null;
  final months =
      -math.log(1 - (amount * monthlyRate) / payment) / math.log(1 + monthlyRate);
  if (!months.isFinite || months <= 0) return null;
  return months;
}

int? payoffMonth(Loan loan) {
  var balance = loan.amount;
  final monthlyRate = loan.interest / 100 / 12;
  final horizon = math.max(1, loan.termMonths);

  for (var i = 1; i <= horizon; i++) {
    balance = balance * (1 + monthlyRate) - loan.monthlyPayment;
    if (balance <= 0) return i;
  }
  return null;
}

List<Map<String, num>> generateSpots(Loan loan) {
  var balance = loan.amount;
  final monthlyRate = loan.interest / 100 / 12;
  final spots = <Map<String, num>>[
    {'month': 0, 'balance': double.parse(balance.toStringAsFixed(2))}
  ];
  final horizon = math.max(1, loan.termMonths);

  for (var i = 1; i <= horizon; i++) {
    balance = balance * (1 + monthlyRate) - loan.monthlyPayment;
    if (balance <= 0) {
      spots.add({'month': i, 'balance': 0});
      break;
    }
    spots.add({'month': i, 'balance': double.parse(balance.toStringAsFixed(2))});
  }
  return spots;
}

double balanceAtMonth(Loan loan, double month) {
  final spots = generateSpots(loan);
  var last = spots.first;
  for (final s in spots) {
    if ((s['month'] as num).toDouble() > month) break;
    last = s;
  }
  return (last['balance'] as num).toDouble();
}

double xInterval(double maxX) {
  const candidates = [6.0, 12.0, 18.0, 24.0, 36.0, 48.0, 60.0];
  for (final c in candidates) {
    if (maxX / c <= 8) return c;
  }
  return 60.0;
}

class ConvertedApp extends StatelessWidget {
  const ConvertedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Converted Finance App',
      theme: ThemeData.dark(useMaterial3: true),
      home: const FinanceRoot(),
    );
  }
}

class FinanceRoot extends StatefulWidget {
  const FinanceRoot({super.key});

  @override
  State<FinanceRoot> createState() => _FinanceRootState();
}

class _FinanceRootState extends State<FinanceRoot> {
  static const _loansKey = 'converted-app-loans-v1';
  static const _spendingKey = 'converted-app-spending-v1';
  static const _investingKey = 'converted-app-investing-v1';

  AppPage _currentPage = AppPage.dashboard;
  List<Loan> _loans = [];
  SpendingData _spendingData = SpendingData();
  InvestingData _investingData = InvestingData();

  @override
  void initState() {
    super.initState();
    _loadPersistedData();
  }

  Future<void> _loadPersistedData() async {
    final prefs = await SharedPreferences.getInstance();
    final loansRaw = prefs.getString(_loansKey);
    final spendingRaw = prefs.getString(_spendingKey);
    final investingRaw = prefs.getString(_investingKey);

    setState(() {
      if (loansRaw != null && loansRaw.isNotEmpty) {
        final decoded = jsonDecode(loansRaw) as List<dynamic>;
        _loans =
            decoded.map((e) => Loan.fromJson(e as Map<String, dynamic>)).toList();
      }
      if (spendingRaw != null && spendingRaw.isNotEmpty) {
        _spendingData =
            SpendingData.fromJson(jsonDecode(spendingRaw) as Map<String, dynamic>);
      }
      if (investingRaw != null && investingRaw.isNotEmpty) {
        _investingData = InvestingData.fromJson(
            jsonDecode(investingRaw) as Map<String, dynamic>);
      }
    });
  }

  Future<void> _persistAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _loansKey,
      jsonEncode(_loans.map((e) => e.toJson()).toList()),
    );
    await prefs.setString(_spendingKey, jsonEncode(_spendingData.toJson()));
    await prefs.setString(_investingKey, jsonEncode(_investingData.toJson()));
  }

  void _updateLoans(List<Loan> next) {
    setState(() => _loans = next);
    _persistAll();
  }

  void _updateSpending(SpendingData next) {
    setState(() => _spendingData = next);
    _persistAll();
  }

  void _updateInvesting(InvestingData next) {
    setState(() => _investingData = next);
    _persistAll();
  }

  double get _spendingIncome => _toDouble(_spendingData.income);
  double get _spendingSpend => _toDouble(_spendingData.spend);
  double get _spendingNet => _spendingIncome - _spendingSpend;
  double get _investingValue => _toDouble(_investingData.portfolioValue);
  double get _totalLoanDue =>
      _loans.fold<double>(0, (sum, loan) => sum + loan.amount);
  int get _activeLoans => _loans.length;
  int get _shownLoans => _loans.where((e) => e.showOnChart).length;
  double get _totalEarnings => _investingValue + _spendingNet - _totalLoanDue;

  @override
  Widget build(BuildContext context) {
    final cards = [
      DashboardCardData(
        title: 'Loans',
        accent: const Color(0xFF57A6FF),
        metrics: {
          'Active Loans': '$_activeLoans',
          'Shown on Graph': '$_shownLoans',
          'Total Due': _money(_totalLoanDue),
        },
      ),
      DashboardCardData(
        title: 'Investing',
        accent: const Color(0xFF4BD1FF),
        metrics: {
          'Portfolio Value': _money(_investingValue),
          'Today Gain': _money(_toDouble(_investingData.todayGain)),
          'YTD Return':
              '${_investingData.ytdReturn.isEmpty ? '0' : _investingData.ytdReturn}%',
        },
      ),
      DashboardCardData(
        title: 'Spending',
        accent: const Color(0xFF67F39B),
        metrics: {
          'Income': _money(_spendingIncome),
          'Spend': _money(_spendingSpend),
          'Net': _money(_spendingNet),
        },
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF020A16),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _glassCard(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Finance Dashboard',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Converted from React to Flutter',
                          style:
                              TextStyle(color: Color(0xFF7F9FC5), fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: SingleChildScrollView(
                      child: _buildCurrentPage(cards),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentPage(List<DashboardCardData> cards) {
    switch (_currentPage) {
      case AppPage.loans:
        return LoansPage(
          loans: _loans,
          onBack: () => setState(() => _currentPage = AppPage.dashboard),
          onLoansChanged: _updateLoans,
        );
      case AppPage.investing:
        return InvestingPage(
          data: _investingData,
          onBack: () => setState(() => _currentPage = AppPage.dashboard),
          onChanged: _updateInvesting,
        );
      case AppPage.spending:
        return SpendingPage(
          data: _spendingData,
          onBack: () => setState(() => _currentPage = AppPage.dashboard),
          onChanged: _updateSpending,
        );
      case AppPage.dashboard:
        return DashboardPage(
          totalEarnings: _totalEarnings,
          cards: cards,
          onNavigate: (page) => setState(() => _currentPage = page),
        );
    }
  }
}

class DashboardCardData {
  DashboardCardData({
    required this.title,
    required this.accent,
    required this.metrics,
  });

  final String title;
  final Color accent;
  final Map<String, String> metrics;
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.totalEarnings,
    required this.cards,
    required this.onNavigate,
  });

  final double totalEarnings;
  final List<DashboardCardData> cards;
  final ValueChanged<AppPage> onNavigate;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _glassCard(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total Earnings', style: TextStyle(fontSize: 18)),
              Text(
                _money(totalEarnings),
                style: const TextStyle(
                  color: Color(0xFF59F69C),
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: cards.map((card) {
            final page = switch (card.title.toLowerCase()) {
              'loans' => AppPage.loans,
              'investing' => AppPage.investing,
              'spending' => AppPage.spending,
              _ => AppPage.dashboard,
            };
            return SizedBox(
              width: 350,
              child: _dashboardCard(card, () => onNavigate(page)),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class LoansPage extends StatefulWidget {
  const LoansPage({
    super.key,
    required this.loans,
    required this.onLoansChanged,
    required this.onBack,
  });

  final List<Loan> loans;
  final ValueChanged<List<Loan>> onLoansChanged;
  final VoidCallback onBack;

  @override
  State<LoansPage> createState() => _LoansPageState();
}

class _LoansPageState extends State<LoansPage> {
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _interestCtrl = TextEditingController();
  final _paymentCtrl = TextEditingController();
  final _monthsCtrl = TextEditingController();

  String? _lastEdited;
  bool _showCombined = true;
  String? _message;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _interestCtrl.dispose();
    _paymentCtrl.dispose();
    _monthsCtrl.dispose();
    super.dispose();
  }

  List<Loan> get _allGraphLoans => widget.loans
      .where((loan) => loan.amount > 0 && loan.monthlyPayment > 0)
      .toList(growable: false);

  List<Loan> get _visibleLoans => widget.loans
      .where((loan) =>
          loan.amount > 0 &&
          loan.monthlyPayment > 0 &&
          loan.showOnChart)
      .toList(growable: false);

  void _updateInterdependentFields(String changed) {
    final amount = _toDouble(_amountCtrl.text);
    final interest = _toDouble(_interestCtrl.text);
    final payment = _toDouble(_paymentCtrl.text);
    final months = _toDouble(_monthsCtrl.text);

    if (changed == 'payment') _lastEdited = 'payment';
    if (changed == 'months') _lastEdited = 'months';

    if (amount <= 0 || interest < 0) return;

    if ((changed == 'amount' || changed == 'interest') && _lastEdited == 'payment') {
      final computed = calculateMonthsFromPayment(amount, interest, payment);
      if (computed != null) _monthsCtrl.text = '${computed.ceil()}';
      return;
    }

    if ((changed == 'amount' || changed == 'interest') && _lastEdited == 'months') {
      final computed = calculateMonthlyPayment(amount, interest, months);
      if (computed != null) _paymentCtrl.text = computed.toStringAsFixed(2);
      return;
    }

    if (_lastEdited == 'payment') {
      final computed = calculateMonthsFromPayment(amount, interest, payment);
      if (computed != null) _monthsCtrl.text = '${computed.ceil()}';
    } else if (_lastEdited == 'months') {
      final computed = calculateMonthlyPayment(amount, interest, months);
      if (computed != null) _paymentCtrl.text = computed.toStringAsFixed(2);
    }
  }

  void _addLoan() {
    final amount = _toDouble(_amountCtrl.text);
    final interest = _toDouble(_interestCtrl.text);
    double monthlyPayment = _toDouble(_paymentCtrl.text);
    int termMonths = _toDouble(_monthsCtrl.text).ceil();

    if (amount <= 0 || interest < 0) {
      setState(() => _message = 'Please enter valid loan amount and interest rate.');
      return;
    }
    if (termMonths <= 0 && monthlyPayment > 0) {
      final computedMonths =
          calculateMonthsFromPayment(amount, interest, monthlyPayment);
      termMonths = computedMonths?.ceil() ?? 0;
    }
    if (monthlyPayment <= 0 && termMonths > 0) {
      monthlyPayment =
          calculateMonthlyPayment(amount, interest, termMonths.toDouble()) ?? 0;
    }
    if (monthlyPayment <= 0 || termMonths <= 0) {
      setState(
          () => _message = 'Enter valid monthly payment or valid number of months.');
      return;
    }

    final loan = Loan(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: _nameCtrl.text.trim().isEmpty
          ? 'Loan ${widget.loans.length + 1}'
          : _nameCtrl.text.trim(),
      amount: amount,
      interest: interest,
      monthlyPayment: double.parse(monthlyPayment.toStringAsFixed(2)),
      termMonths: termMonths,
      showOnChart: true,
    );

    if (cannotPayOff(loan)) {
      setState(() {
        _message =
            'Payment too low. Minimum: ${_money(minimumPayment(loan))} / month';
      });
      return;
    }

    final next = [...widget.loans, loan];
    widget.onLoansChanged(next);
    setState(() => _message = null);
    _nameCtrl.clear();
    _amountCtrl.clear();
    _interestCtrl.clear();
    _paymentCtrl.clear();
    _monthsCtrl.clear();
    _lastEdited = null;
  }

  void _toggleShow(String id) {
    final next = widget.loans
        .map((loan) =>
            loan.id == id ? loan.copyWith(showOnChart: !loan.showOnChart) : loan)
        .toList(growable: false);
    widget.onLoansChanged(next);
  }

  void _removeLoan(String id) {
    final next = widget.loans.where((loan) => loan.id != id).toList(growable: false);
    widget.onLoansChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final allLoans = _allGraphLoans;
    final visibleLoans = _visibleLoans;
    final maxX = _maxX(allLoans);
    final chartRows = _buildChartRows(maxX, allLoans, visibleLoans);
    final maxY = _maxY(chartRows, visibleLoans, _showCombined);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextButton.icon(
          onPressed: widget.onBack,
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFD9E9FF),
            backgroundColor: const Color(0x66091C35),
            side: const BorderSide(color: Color(0x807FA6DC)),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: const Icon(Icons.arrow_back),
          label: const Text('Back'),
        ),
        const SizedBox(height: 8),
        const Text(
          'Loan Analyzer',
          style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        _glassCard(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Checkbox(
                value: _showCombined,
                onChanged: (v) => setState(() => _showCombined = v ?? true),
              ),
              const Expanded(child: Text('Show combined graph (all loans)')),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _glassCard(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            height: 300,
            child: allLoans.isEmpty
                ? const Center(
                    child: Text(
                      'Add a loan to see the chart',
                      style: TextStyle(color: Color(0xFF87A5CC)),
                    ),
                  )
                : LineChart(
                    _lineChartData(
                      chartRows: chartRows,
                      maxX: maxX,
                      maxY: maxY,
                      visibleLoans: visibleLoans,
                      showCombined: _showCombined,
                    ),
                  ),
          ),
        ),
        if (widget.loans.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('Your Loans',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ...widget.loans.asMap().entries.map((entry) {
            final i = entry.key;
            final loan = entry.value;
            final payoff = payoffMonth(loan);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _glassCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    Container(
                      height: 4,
                      color: cannotPayOff(loan)
                          ? const Color(0xFF7B8799)
                          : loanColors[i % loanColors.length],
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  loan.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700, fontSize: 16),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${_money(loan.amount)} · ${loan.interest}% APR · ${_money(loan.monthlyPayment)}/mo · ${loan.termMonths} months',
                                  style: const TextStyle(
                                      color: Color(0xFF88A8D0), fontSize: 13),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  payoff != null
                                      ? 'Payoff: $payoff mo (${(payoff / 12).toStringAsFixed(1)} yr)'
                                      : 'Payoff: Never',
                                  style: const TextStyle(color: Color(0xFFB8CEEA)),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Checkbox(
                                    value: loan.showOnChart,
                                    onChanged: (_) => _toggleShow(loan.id),
                                  ),
                                  const Text('Show graph'),
                                ],
                              ),
                              const SizedBox(height: 6),
                              OutlinedButton(
                                onPressed: () => _removeLoan(loan.id),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (cannotPayOff(loan))
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        color: const Color(0x292EF444),
                        child: Text(
                          'Payment too low. Minimum needed: ${_money(minimumPayment(loan))}/mo',
                          style: const TextStyle(color: Color(0xFFFF9C9C)),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),
        ],
        const SizedBox(height: 8),
        const Text('Add Loan',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        _glassCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              _textField(_nameCtrl, 'Loan Name (optional)'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _textField(
                      _amountCtrl,
                      'Loan Amount',
                      onChanged: (_) => _updateInterdependentFields('amount'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _textField(
                      _interestCtrl,
                      'Interest Rate %',
                      onChanged: (_) => _updateInterdependentFields('interest'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _textField(
                      _paymentCtrl,
                      'Monthly Payment',
                      onChanged: (_) => _updateInterdependentFields('payment'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _textField(
                      _monthsCtrl,
                      'Number of Months',
                      onChanged: (_) => _updateInterdependentFields('months'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _addLoan,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3CA0FF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Add Loan'),
                ),
              ),
              if (_message != null) ...[
                const SizedBox(height: 8),
                Text(
                  _message!,
                  style: const TextStyle(color: Color(0xFFFFAFAF)),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _textField(
    TextEditingController controller,
    String hint, {
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF7F9FC5)),
        filled: true,
        fillColor: const Color(0x9E081B32),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

class SpendingPage extends StatelessWidget {
  const SpendingPage({
    super.key,
    required this.data,
    required this.onChanged,
    required this.onBack,
  });

  final SpendingData data;
  final ValueChanged<SpendingData> onChanged;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final income = _toDouble(data.income);
    final spend = _toDouble(data.spend);
    final net = income - spend;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextButton.icon(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back),
          label: const Text('Back'),
        ),
        const Text('Cash Flow',
            style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        _glassCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Net Income',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(_money(net),
                  style: const TextStyle(
                      fontSize: 42, fontWeight: FontWeight.w800)),
              const Text('Income - Spend',
                  style: TextStyle(color: Color(0xFF7F9FC5))),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _spendingPanel(
                title: 'Spend',
                value: _money(spend),
                hint: 'Spend',
                currentValue: data.spend,
                onChanged: (v) => onChanged(data.copyWith(spend: v)),
                footerLabel: 'Current',
                footerValue: _money(spend),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _spendingPanel(
                title: 'Income',
                value: _money(income),
                hint: 'Income',
                currentValue: data.income,
                onChanged: (v) => onChanged(data.copyWith(income: v)),
                footerLabel: 'Net',
                footerValue: _money(net),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _spendingPanel({
    required String title,
    required String value,
    required String hint,
    required String currentValue,
    required ValueChanged<String> onChanged,
    required String footerLabel,
    required String footerValue,
  }) {
    return _glassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(value,
              style:
                  const TextStyle(fontSize: 42, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          TextField(
            onChanged: onChanged,
            controller: TextEditingController(text: currentValue)
              ..selection = TextSelection.collapsed(offset: currentValue.length),
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: hint,
              filled: true,
              fillColor: const Color(0x9E081B32),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(footerLabel, style: const TextStyle(color: Color(0xFF8DAED8))),
              Text(footerValue,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }
}

class InvestingPage extends StatelessWidget {
  const InvestingPage({
    super.key,
    required this.data,
    required this.onChanged,
    required this.onBack,
  });

  final InvestingData data;
  final ValueChanged<InvestingData> onChanged;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextButton.icon(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back),
          label: const Text('Back'),
        ),
        const Text('Investments',
            style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        _glassCard(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${data.ytdReturn.isEmpty ? '0.00' : data.ytdReturn}%',
                  style: const TextStyle(color: Color(0xFF7F9FC5))),
              const SizedBox(height: 6),
              Text(
                _money(_toDouble(data.portfolioValue)),
                style:
                    const TextStyle(fontSize: 58, fontWeight: FontWeight.w800),
              ),
              const Text(
                'total balance',
                style: TextStyle(
                  color: Color(0xFF8FAED5),
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _input(
                      data.portfolioValue,
                      'Portfolio Value',
                      (v) => onChanged(data.copyWith(portfolioValue: v)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _input(
                      data.todayGain,
                      'Today Gain',
                      (v) => onChanged(data.copyWith(todayGain: v)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _input(
                      data.ytdReturn,
                      'YTD Return %',
                      (v) => onChanged(data.copyWith(ytdReturn: v)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: ['1W', '1M', 'YTD', '3M', '1Y', 'ALL']
                    .map((tab) => Chip(
                          label: Text(tab),
                          backgroundColor: tab == '1M'
                              ? const Color(0xFF2A6AC6)
                              : const Color(0x66091C35),
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _input(String value, String hint, ValueChanged<String> onChanged) {
    return TextField(
      controller: TextEditingController(text: value)
        ..selection = TextSelection.collapsed(offset: value.length),
      onChanged: onChanged,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: const Color(0x9E081B32),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

Widget _glassCard({required Widget child, required EdgeInsets padding}) {
  return Container(
    padding: padding,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0x425D8FD4)),
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xEB08162B), Color(0xEB030F1E)],
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x59000000),
          blurRadius: 34,
          offset: Offset(0, 12),
        ),
      ],
    ),
    child: child,
  );
}

Widget _dashboardCard(DashboardCardData card, VoidCallback onTap) {
  return GestureDetector(
    onTap: onTap,
    child: Stack(
      children: [
        _glassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(card.title,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Row(
                children: card.metrics.entries
                    .map(
                      (e) => Expanded(
                        child: Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0x9E0E2545),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(e.key,
                                  style: const TextStyle(
                                      fontSize: 11, color: Color(0xFF8FAED5))),
                              const SizedBox(height: 2),
                              Text(e.value,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: Container(height: 3, color: card.accent),
        ),
      ],
    ),
  );
}

LineChartData _lineChartData({
  required List<Map<String, double>> chartRows,
  required double maxX,
  required double maxY,
  required List<Loan> visibleLoans,
  required bool showCombined,
}) {
  final bars = <LineChartBarData>[];

  if (showCombined) {
    bars.add(
      LineChartBarData(
        spots: chartRows
            .map((row) => FlSpot(row['month']!, row['combinedAll'] ?? 0))
            .toList(growable: false),
        color: Colors.white,
        barWidth: 2,
        isCurved: true,
        dotData: const FlDotData(show: false),
        dashArray: [6, 4],
      ),
    );
  }

  for (var i = 0; i < visibleLoans.length; i++) {
    final loan = visibleLoans[i];
    bars.add(
      LineChartBarData(
        spots: chartRows
            .map((row) => FlSpot(row['month']!, row['loan_${loan.id}'] ?? 0))
            .toList(growable: false),
        color: loanColors[i % loanColors.length],
        barWidth: 3,
        isCurved: true,
        dotData: const FlDotData(show: false),
      ),
    );
  }

  return LineChartData(
    minX: 0,
    maxX: maxX,
    minY: 0,
    maxY: maxY,
    lineBarsData: bars,
    gridData: FlGridData(
      show: true,
      drawVerticalLine: false,
      getDrawingHorizontalLine: (_) => const FlLine(
        color: Color(0x2E82A4D2),
        strokeWidth: 1,
      ),
    ),
    borderData: FlBorderData(show: false),
    titlesData: FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          interval: xInterval(maxX),
          getTitlesWidget: (value, _) => Text(
            value.toInt().toString(),
            style: const TextStyle(color: Color(0xFF84A7D4), fontSize: 11),
          ),
        ),
      ),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          interval: math.max(1, (maxY / 5).ceilToDouble()),
          reservedSize: 54,
          getTitlesWidget: (value, _) => Text(
            value >= 1000
                ? '\$${(value / 1000).toStringAsFixed(0)}k'
                : '\$${value.toStringAsFixed(0)}',
            style: const TextStyle(color: Color(0xFF84A7D4), fontSize: 11),
          ),
        ),
      ),
    ),
    lineTouchData: const LineTouchData(
      enabled: true,
      handleBuiltInTouches: true,
    ),
  );
}

List<Map<String, double>> _buildChartRows(
  double maxX,
  List<Loan> allGraphLoans,
  List<Loan> visibleLoans,
) {
  final rows = <Map<String, double>>[];
  if (allGraphLoans.isEmpty) return rows;

  for (var month = 0; month <= maxX; month++) {
    final row = <String, double>{'month': month.toDouble()};
    for (final loan in visibleLoans) {
      row['loan_${loan.id}'] = balanceAtMonth(loan, month.toDouble());
    }
    row['combinedAll'] = allGraphLoans.fold<double>(
      0,
      (sum, loan) => sum + balanceAtMonth(loan, month.toDouble()),
    );
    rows.add(row);
  }
  return rows;
}

double _maxX(List<Loan> loans) {
  if (loans.isEmpty) return 1;
  return loans
      .map((loan) => (generateSpots(loan).last['month'] as num).toDouble())
      .fold<double>(1, math.max);
}

double _maxY(
  List<Map<String, double>> rows,
  List<Loan> visibleLoans,
  bool showCombined,
) {
  if (rows.isEmpty) return 100;
  final values = <double>[];
  for (final row in rows) {
    for (final loan in visibleLoans) {
      values.add(row['loan_${loan.id}'] ?? 0);
    }
    if (showCombined) values.add(row['combinedAll'] ?? 0);
  }
  final raw = values.isEmpty ? 100 : values.reduce(math.max);
  return math.max(100, (raw * 1.1).ceilToDouble());
}

double _toDouble(String? value) => double.tryParse((value ?? '').trim()) ?? 0;

String _money(double value) => '\$${value.toStringAsFixed(2)}';
