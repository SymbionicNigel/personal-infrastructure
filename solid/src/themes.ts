import { createTheme } from '@suid/material';

// Found on https://looka.com/blog/vintage-color-palettes/ all of #5 with brown from 11
export const mantanaRegular60s = createTheme({
	typography: {
		fontFamily: 'Mantana-regular',
	},
	palette: {
		primary: {
			main: '#669fb2',
			light: '#e8b877',
			dark: '#dd802c',
		},
		secondary: {
			main: '#ae9068',
			light: '#dadfe1',
			dark: '#3e2a20',
		},
		mode: 'light',
	},
});
