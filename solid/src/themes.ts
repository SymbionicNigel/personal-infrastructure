import { createTheme } from '@suid/material';

// Found on https://looka.com/blog/vintage-color-palettes/ all of #5 with brown from 11
export const mantanaRegular60s = createTheme({
	typography: {
		fontFamily: 'Mantana-regular',
	},
	palette: {
		mode: 'dark',
		primary: {
			main: '#669fb2',
		},
		secondary: {
			main: '#87aa7e',
		},
		background: {
			default: '#271e16',
			paper: '#31281d',
		},
		warning: {
			main: '#edbf02',
		},
		error: {
			main: '#e06c21',
		},
		info: {
			main: '#0288d1',
		},
		divider: '#2f201b',
		success: {
			main: '#005427',
		},
	},
});
