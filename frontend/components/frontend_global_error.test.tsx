import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import {
  FrontendGlobalErrorBoundary,
  ContractError,
  NetworkError,
  TransactionError,
  ErrorReport,
  LOG_RATE_LIMIT,
  LOG_RATE_WINDOW_MS,
  shouldLog,
  _logState,
  _resetLogState,
} from './frontend_global_error';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

const originalConsoleError = console.error;
beforeAll(() => { console.error = jest.fn(); });
afterAll(() => { console.error = originalConsoleError; });
beforeEach(() => {
  jest.clearAllMocks();
  _resetLogState();
});

/** Helper component that always throws the given error during render. */
const Throw = ({ error }: { error: Error }) => { throw error; };

// ---------------------------------------------------------------------------
// Custom error classes
// ---------------------------------------------------------------------------

describe('Custom error classes', () => {
  it('ContractError has correct name and extends Error', () => {
    const e = new ContractError('bad contract');
    expect(e.name).toBe('ContractError');
    expect(e.message).toBe('bad contract');
    expect(e).toBeInstanceOf(Error);
  });

  it('NetworkError has correct name and extends Error', () => {
    const e = new NetworkError('timeout');
    expect(e.name).toBe('NetworkError');
    expect(e.message).toBe('timeout');
    expect(e).toBeInstanceOf(Error);
  });

  it('TransactionError has correct name and extends Error', () => {
    const e = new TransactionError('rejected');
    expect(e.name).toBe('TransactionError');
    expect(e.message).toBe('rejected');
    expect(e).toBeInstanceOf(Error);
  });

  it('ContractError stack is defined', () => {
    const e = new ContractError('stack test');
    expect(e.stack).toBeDefined();
  });

  it('NetworkError stack is defined', () => {
    expect(new NetworkError('x').stack).toBeDefined();
  });

  it('TransactionError stack is defined', () => {
    expect(new TransactionError('x').stack).toBeDefined();
  });
});

// ---------------------------------------------------------------------------
// Logging bounds — shouldLog() unit tests
// ---------------------------------------------------------------------------

describe('shouldLog() rate limiter', () => {
  it('returns true for the first LOG_RATE_LIMIT calls within a window', () => {
    const now = 1_000_000;
    for (let i = 0; i < LOG_RATE_LIMIT; i++) {
      expect(shouldLog(now)).toBe(true);
    }
  });

  it('returns false once LOG_RATE_LIMIT is exceeded within the same window', () => {
    const now = 2_000_000;
    for (let i = 0; i < LOG_RATE_LIMIT; i++) shouldLog(now);
    expect(shouldLog(now)).toBe(false);
  });

  it('resets and returns true after the window expires', () => {
    const now = 3_000_000;
    for (let i = 0; i < LOG_RATE_LIMIT; i++) shouldLog(now);
    expect(shouldLog(now)).toBe(false);
    // Advance past the window.
    expect(shouldLog(now + LOG_RATE_WINDOW_MS)).toBe(true);
  });

  it('increments _logState.count on each allowed call', () => {
    const now = 4_000_000;
    shouldLog(now);
    shouldLog(now);
    expect(_logState.count).toBe(2);
  });

  it('does not increment count beyond LOG_RATE_LIMIT', () => {
    const now = 5_000_000;
    for (let i = 0; i < LOG_RATE_LIMIT + 3; i++) shouldLog(now);
    expect(_logState.count).toBe(LOG_RATE_LIMIT);
  });

  it('resets windowStart when a new window begins', () => {
    const now = 6_000_000;
    shouldLog(now);
    const newNow = now + LOG_RATE_WINDOW_MS + 1;
    shouldLog(newNow);
    expect(_logState.windowStart).toBe(newNow);
  });

  it('_resetLogState zeroes count and windowStart', () => {
    shouldLog(7_000_000);
    _resetLogState();
    expect(_logState.count).toBe(0);
    expect(_logState.windowStart).toBe(0);
  });

  it('LOG_RATE_LIMIT is 5', () => {
    expect(LOG_RATE_LIMIT).toBe(5);
  });

  it('LOG_RATE_WINDOW_MS is 60000', () => {
    expect(LOG_RATE_WINDOW_MS).toBe(60_000);
  });

  it('allows exactly LOG_RATE_LIMIT logs then blocks', () => {
    const now = 8_000_000;
    const results: boolean[] = [];
    for (let i = 0; i < LOG_RATE_LIMIT + 2; i++) results.push(shouldLog(now));
    expect(results.slice(0, LOG_RATE_LIMIT).every(Boolean)).toBe(true);
    expect(results[LOG_RATE_LIMIT]).toBe(false);
    expect(results[LOG_RATE_LIMIT + 1]).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// Logging bounds — integration with componentDidCatch
// ---------------------------------------------------------------------------

describe('Logging bounds — componentDidCatch integration', () => {
  it('calls console.error for the first error (within rate limit)', () => {
    render(
      <FrontendGlobalErrorBoundary>
        <Throw error={new Error('first error')} />
      </FrontendGlobalErrorBoundary>,
    );
    expect(console.error).toHaveBeenCalledWith(
      'Documentation Error Boundary caught an error:',
      expect.any(Error),
      expect.objectContaining({ componentStack: expect.any(String) }),
    );
  });

  it('suppresses console.error after LOG_RATE_LIMIT errors in the same window', () => {
    // Exhaust the rate limit by pre-filling the counter.
    const now = Date.now();
    _logState.windowStart = now;
    _logState.count = LOG_RATE_LIMIT;

    render(
      <FrontendGlobalErrorBoundary>
        <Throw error={new Error('over limit')} />
      </FrontendGlobalErrorBoundary>,
    );
    // Our boundary log message must NOT appear — React's own console.error calls are allowed.
    const ourCalls = (console.error as jest.Mock).mock.calls.filter(
      (args) => args[0] === 'Documentation Error Boundary caught an error:',
    );
    expect(ourCalls).toHaveLength(0);
  });

  it('still calls onError even when console.error is suppressed', () => {
    const onError = jest.fn();
    const now = Date.now();
    _logState.windowStart = now;
    _logState.count = LOG_RATE_LIMIT;

    render(
      <FrontendGlobalErrorBoundary onError={onError}>
        <Throw error={new Error('suppressed log but callback fires')} />
      </FrontendGlobalErrorBoundary>,
    );
    const ourCalls = (console.error as jest.Mock).mock.calls.filter(
      (args) => args[0] === 'Documentation Error Boundary caught an error:',
    );
    expect(ourCalls).toHaveLength(0);
    expect(onError).toHaveBeenCalledTimes(1);
  });

  it('resumes console.error after the rate-limit window resets', () => {
    // Exhaust the window.
    const past = Date.now() - LOG_RATE_WINDOW_MS - 1;
    _logState.windowStart = past;
    _logState.count = LOG_RATE_LIMIT;

    // The window has expired, so the next call should open a new window.
    render(
      <FrontendGlobalErrorBoundary>
        <Throw error={new Error('new window error')} />
      </FrontendGlobalErrorBoundary>,
    );
    const ourCalls = (console.error as jest.Mock).mock.calls.filter(
      (args) => args[0] === 'Documentation Error Boundary caught an error:',
    );
    expect(ourCalls).toHaveLength(1);
  });

  it('onError is always called regardless of rate limit', () => {
    const onError = jest.fn();
    // Render LOG_RATE_LIMIT + 2 separate boundaries to trigger multiple catches.
    for (let i = 0; i < LOG_RATE_LIMIT + 2; i++) {
      _resetLogState(); // reset between renders to isolate; then re-exhaust below
    }
    // Now exhaust the limit and verify onError still fires.
    _logState.windowStart = Date.now();
    _logState.count = LOG_RATE_LIMIT;

    render(
      <FrontendGlobalErrorBoundary onError={onError}>
        <Throw error={new Error('always reported')} />
      </FrontendGlobalErrorBoundary>,
    );
    expect(onError).toHaveBeenCalledTimes(1);
    expect(onError.mock.calls[0][0].message).toBe('always reported');
  });
});

// ---------------------------------------------------------------------------
// Normal rendering (no error)
// ---------------------------------------------------------------------------

describe('Normal rendering (no error)', () => {
  it('renders children when no error is thrown', () => {
    render(
      <FrontendGlobalErrorBoundary>
        <div data-testid="child">Safe Content</div>
      </FrontendGlobalErrorBoundary>,
    );
    expect(screen.getByTestId('child')).toBeTruthy();
    expect(screen.getByText('Safe Content')).toBeTruthy();
  });

  it('renders null when children is omitted', () => {
    const { container } = render(<FrontendGlobalErrorBoundary />);
    expect(container.firstChild).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// Generic error fallback
// ---------------------------------------------------------------------------

describe('Generic error fallback', () => {
  it('renders the default fallback UI on error', () => {
    render(
      <FrontendGlobalErrorBoundary>
        <Throw error={new Error('Simulated crash')} />
      </FrontendGlobalErrorBoundary>,
    );
    expect(screen.getByRole('alert')).toBeTruthy();
    expect(screen.getByText('Documentation Loading Error')).toBeTruthy();
  });

  it('shows the "Try Again" button', () => {
    render(
      <FrontendGlobalErrorBoundary>
        <Throw error={new Error('crash')} />
      </FrontendGlobalErrorBoundary>,
    );
    expect(screen.getByRole('button', { name: 'Try Again' })).toBeTruthy();
  });

  it('shows the "Go Home" button', () => {
    render(
      <FrontendGlobalErrorBoundary>
        <Throw error={new Error('crash')} />
      </FrontendGlobalErrorBoundary>,
    );
    expect(screen.getByRole('button', { name: 'Go Home' })).toBeTruthy();
  });

  it('calls console.error with the caught error', () => {
    render(
      <FrontendGlobalErrorBoundary>
        <Throw error={new Error('Simulated documentation crash')} />
      </FrontendGlobalErrorBoundary>,
    );
    expect(console.error).toHaveBeenCalledWith(
      'Documentation Error Boundary caught an error:',
      expect.any(Error),
      expect.objectContaining({ componentStack: expect.any(String) }),
    );
  });

  it('has role="alert" and aria-live="assertive"', () => {
    render(
      <FrontendGlobalErrorBoundary>
        <Throw error={new Error('crash')} />
      </FrontendGlobalErrorBoundary>,
    );
    expect(screen.getByRole('alert').getAttribute('aria-live')).toBe('assertive');
  });
});

// ---------------------------------------------------------------------------
// Smart contract error fallback
// ---------------------------------------------------------------------------

describe('Smart contract error fallback', () => {
  const contractErrors: Array<[string, Error]> = [
    ['ContractError instance', new ContractError('contract call failed')],
    ['NetworkError instance', new NetworkError('horizon timeout')],
    ['TransactionError instance', new TransactionError('tx rejected')],
    ['stellar keyword', new Error('stellar network error')],
    ['soroban keyword', new Error('soroban invocation failed')],
    ['transaction keyword', new Error('transaction simulation error')],
    ['blockchain keyword', new Error('blockchain ledger closed')],
    ['wallet keyword', new Error('wallet connection lost')],
    ['xdr keyword', new Error('xdr decode error')],
    ['horizon keyword', new Error('horizon api error')],
  ];

  contractErrors.forEach(([label, err]) => {
    it(`shows Smart Contract Error for ${label}`, () => {
      render(
        <FrontendGlobalErrorBoundary>
          <Throw error={err} />
        </FrontendGlobalErrorBoundary>,
      );
      expect(screen.getByText('Smart Contract Error')).toBeTruthy();
    });
  });

  it('shows blockchain-specific guidance text', () => {
    render(
      <FrontendGlobalErrorBoundary>
        <Throw error={new ContractError('insufficient funds')} />
      </FrontendGlobalErrorBoundary>,
    );
    expect(screen.getByText(/Check your wallet balance/i)).toBeTruthy();
  });

  it('does NOT show Documentation Loading Error for contract errors', () => {
    render(
      <FrontendGlobalErrorBoundary>
        <Throw error={new ContractError('bad call')} />
      </FrontendGlobalErrorBoundary>,
    );
    expect(screen.queryByText('Documentation Loading Error')).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// Custom fallback prop
// ---------------------------------------------------------------------------

describe('Custom fallback prop', () => {
  it('renders the custom fallback when provided', () => {
    render(
      <FrontendGlobalErrorBoundary fallback={<div data-testid="cf">Custom Error View</div>}>
        <Throw error={new Error('crash')} />
      </FrontendGlobalErrorBoundary>,
    );
    expect(screen.getByTestId('cf')).toBeTruthy();
    expect(screen.getByText('Custom Error View')).toBeTruthy();
  });

  it('does NOT render the default fallback when custom fallback is provided', () => {
    render(
      <FrontendGlobalErrorBoundary fallback={<div>Custom</div>}>
        <Throw error={new Error('crash')} />
      </FrontendGlobalErrorBoundary>,
    );
    expect(screen.queryByText('Documentation Loading Error')).toBeNull();
    expect(screen.queryByText('Smart Contract Error')).toBeNull();
  });

  it('custom fallback overrides smart contract fallback too', () => {
    render(
      <FrontendGlobalErrorBoundary fallback={<div data-testid="cf2">My Fallback</div>}>
        <Throw error={new ContractError('bad')} />
      </FrontendGlobalErrorBoundary>,
    );
    expect(screen.getByTestId('cf2')).toBeTruthy();
    expect(screen.queryByText('Smart Contract Error')).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// Recovery via Try Again
// ---------------------------------------------------------------------------

describe('Recovery via Try Again', () => {
  it('re-renders children after clicking Try Again when error is resolved', () => {
    let shouldThrow = true;
    const RecoverableComponent = () => {
      if (shouldThrow) throw new Error('Temporary error');
      return <div>Recovered Content</div>;
    };
    render(
      <FrontendGlobalErrorBoundary>
        <RecoverableComponent />
      </FrontendGlobalErrorBoundary>,
    );
    expect(screen.getByText('Documentation Loading Error')).toBeTruthy();
    shouldThrow = false;
    fireEvent.click(screen.getByRole('button', { name: 'Try Again' }));
    expect(screen.getByText('Recovered Content')).toBeTruthy();
    expect(screen.queryByText('Documentation Loading Error')).toBeNull();
  });

  it('shows the fallback again if the child still throws after retry', () => {
    render(
      <FrontendGlobalErrorBoundary>
        <Throw error={new Error('persistent error')} />
      </FrontendGlobalErrorBoundary>,
    );
    fireEvent.click(screen.getByRole('button', { name: 'Try Again' }));
    expect(screen.getByText('Documentation Loading Error')).toBeTruthy();
  });

  it('recovery works for contract errors too', () => {
    let shouldThrow = true;
    const RecoverableContract = () => {
      if (shouldThrow) throw new ContractError('contract failed');
      return <div>Contract OK</div>;
    };
    render(
      <FrontendGlobalErrorBoundary>
        <RecoverableContract />
      </FrontendGlobalErrorBoundary>,
    );
    expect(screen.getByText('Smart Contract Error')).toBeTruthy();
    shouldThrow = false;
    fireEvent.click(screen.getByRole('button', { name: 'Try Again' }));
    expect(screen.getByText('Contract OK')).toBeTruthy();
  });
});

// ---------------------------------------------------------------------------
// onError callback
// ---------------------------------------------------------------------------

describe('onError callback', () => {
  it('calls onError with a structured report when an error is caught', () => {
    const onError = jest.fn();
    render(
      <FrontendGlobalErrorBoundary onError={onError}>
        <Throw error={new Error('callback test')} />
      </FrontendGlobalErrorBoundary>,
    );
    expect(onError).toHaveBeenCalledTimes(1);
    const report: ErrorReport = onError.mock.calls[0][0];
    expect(report.message).toBe('callback test');
    expect(report.timestamp).toBeTruthy();
    expect(typeof report.isSmartContractError).toBe('boolean');
    expect(report.errorName).toBe('Error');
  });

  it('sets isSmartContractError=true for ContractError', () => {
    const onError = jest.fn();
    render(
      <FrontendGlobalErrorBoundary onError={onError}>
        <Throw error={new ContractError('bad')} />
      </FrontendGlobalErrorBoundary>,
    );
    expect(onError.mock.calls[0][0].isSmartContractError).toBe(true);
  });

  it('sets isSmartContractError=false for generic errors', () => {
    const onError = jest.fn();
    render(
      <FrontendGlobalErrorBoundary onError={onError}>
        <Throw error={new Error('generic')} />
      </FrontendGlobalErrorBoundary>,
    );
    expect(onError.mock.calls[0][0].isSmartContractError).toBe(false);
  });

  it('does not throw if onError is not provided', () => {
    expect(() =>
      render(
        <FrontendGlobalErrorBoundary>
          <Throw error={new Error('no callback')} />
        </FrontendGlobalErrorBoundary>,
      ),
    ).not.toThrow();
  });

  it('report.errorName matches the error class name', () => {
    const onError = jest.fn();
    render(
      <FrontendGlobalErrorBoundary onError={onError}>
        <Throw error={new NetworkError('net')} />
      </FrontendGlobalErrorBoundary>,
    );
    expect(onError.mock.calls[0][0].errorName).toBe('NetworkError');
  });

  it('report.timestamp is a valid ISO 8601 string', () => {
    const onError = jest.fn();
    render(
      <FrontendGlobalErrorBoundary onError={onError}>
        <Throw error={new Error('ts test')} />
      </FrontendGlobalErrorBoundary>,
    );
    expect(() => new Date(onError.mock.calls[0][0].timestamp)).not.toThrow();
    expect(new Date(onError.mock.calls[0][0].timestamp).toISOString()).toBe(
      onError.mock.calls[0][0].timestamp,
    );
  });
});

// ---------------------------------------------------------------------------
// Accessibility
// ---------------------------------------------------------------------------

describe('Accessibility', () => {
  it('fallback container has role alert', () => {
    render(
      <FrontendGlobalErrorBoundary>
        <Throw error={new Error('a11y test')} />
      </FrontendGlobalErrorBoundary>,
    );
    expect(screen.getByRole('alert')).toBeTruthy();
  });

  it('Try Again button has aria-label', () => {
    render(
      <FrontendGlobalErrorBoundary>
        <Throw error={new Error('a11y')} />
      </FrontendGlobalErrorBoundary>,
    );
    expect(
      screen.getByRole('button', { name: 'Try Again' }).getAttribute('aria-label'),
    ).toBe('Try Again');
  });

  it('Go Home button has aria-label', () => {
    render(
      <FrontendGlobalErrorBoundary>
        <Throw error={new Error('a11y')} />
      </FrontendGlobalErrorBoundary>,
    );
    expect(
      screen.getByRole('button', { name: 'Go Home' }).getAttribute('aria-label'),
    ).toBe('Go Home');
  });

  it('icon span is aria-hidden', () => {
    const { container } = render(
      <FrontendGlobalErrorBoundary>
        <Throw error={new Error('icon test')} />
      </FrontendGlobalErrorBoundary>,
    );
    expect(container.querySelector('[aria-hidden="true"]')).toBeTruthy();
  });

  it('contract fallback also has role alert', () => {
    render(
      <FrontendGlobalErrorBoundary>
        <Throw error={new ContractError('a11y contract')} />
      </FrontendGlobalErrorBoundary>,
    );
    expect(screen.getByRole('alert').getAttribute('aria-live')).toBe('assertive');
  });
});

// ---------------------------------------------------------------------------
// Error classification edge cases
// ---------------------------------------------------------------------------

describe('Error classification edge cases', () => {
  it('classifies NetworkError as smart contract error', () => {
    const onError = jest.fn();
    render(
      <FrontendGlobalErrorBoundary onError={onError}>
        <Throw error={new NetworkError('timeout')} />
      </FrontendGlobalErrorBoundary>,
    );
    expect(onError.mock.calls[0][0].isSmartContractError).toBe(true);
  });

  it('classifies TransactionError as smart contract error', () => {
    const onError = jest.fn();
    render(
      <FrontendGlobalErrorBoundary onError={onError}>
        <Throw error={new TransactionError('rejected')} />
      </FrontendGlobalErrorBoundary>,
    );
    expect(onError.mock.calls[0][0].isSmartContractError).toBe(true);
  });

  it('classifies plain Error with invoke keyword as contract error', () => {
    render(
      <FrontendGlobalErrorBoundary>
        <Throw error={new Error('invoke failed')} />
      </FrontendGlobalErrorBoundary>,
    );
    expect(screen.getByText('Smart Contract Error')).toBeTruthy();
  });

  it('does not classify a plain TypeError as a contract error', () => {
    render(
      <FrontendGlobalErrorBoundary>
        <Throw error={new TypeError('cannot read property')} />
      </FrontendGlobalErrorBoundary>,
    );
    expect(screen.getByText('Documentation Loading Error')).toBeTruthy();
    expect(screen.queryByText('Smart Contract Error')).toBeNull();
  });

  it('handles errors with empty messages gracefully', () => {
    expect(() =>
      render(
        <FrontendGlobalErrorBoundary>
          <Throw error={new Error('')} />
        </FrontendGlobalErrorBoundary>,
      ),
    ).not.toThrow();
    expect(screen.getByRole('alert')).toBeTruthy();
  });

  it('classifies error with ledger keyword as contract error', () => {
    render(
      <FrontendGlobalErrorBoundary>
        <Throw error={new Error('ledger sequence mismatch')} />
      </FrontendGlobalErrorBoundary>,
    );
    expect(screen.getByText('Smart Contract Error')).toBeTruthy();
  });

  it('classifies error with contract keyword in name as contract error', () => {
    const e = new Error('something failed');
    e.name = 'ContractExecutionError';
    render(
      <FrontendGlobalErrorBoundary>
        <Throw error={e} />
      </FrontendGlobalErrorBoundary>,
    );
    expect(screen.getByText('Smart Contract Error')).toBeTruthy();
  });
});
