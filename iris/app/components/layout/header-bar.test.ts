import { expect, test } from 'vitest';
import { titleCaseHost } from './header-bar';

test('capitalizes every dot-separated label', () => {
  expect(titleCaseHost('example.com')).toBe('Example.Com');
});

test('handles a single label', () => {
  expect(titleCaseHost('localhost')).toBe('Localhost');
});

test('leaves already-capitalized labels intact', () => {
  expect(titleCaseHost('Example.Com')).toBe('Example.Com');
});

test('only touches the first character of each label', () => {
  expect(titleCaseHost('mySite.io')).toBe('MySite.Io');
});

test('returns an empty string unchanged', () => {
  expect(titleCaseHost('')).toBe('');
});
