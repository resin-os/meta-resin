module.exports = [{
	deviceType: `raspberrypi3`,
	suite: `${__dirname}/../suites/os`,
	config: {
		networkWired: false,
		networkWireless: true,
		downloadType: 'local',
		interactiveTests: false, // redundant
		balenaApiKey: process.env.BALENA_CLOUD_API_KEY,
		balenaApiUrl: 'balena-cloud.com',
		organization: process.env.BALENA_CLOUD_ORG
	},
	image: `${__dirname}/balena.img.gz`,
	workers: {
		balenaApplication: process.env.BALENA_CLOUD_APP_NAME,
		apiKey: process.env.BALENA_CLOUD_API_KEY,
	},
},
{
	deviceType: `raspberrypi3`,
	suite: `${__dirname}/../suites/hup`,
	config: {
		networkWired: false,
		networkWireless: true,
		downloadVersion: 'latest',
		downloadType: 'gunzip',
		interactiveTests: false, // redundant
		balenaApiKey: process.env.BALENA_CLOUD_API_KEY,
		balenaApiUrl: 'balena-cloud.com',
		organization: process.env.BALENA_CLOUD_ORG
	},
	image: `${__dirname}/balena-image.docker`,
	workers: {
		balenaApplication: process.env.BALENA_CLOUD_APP_NAME,
		apiKey: process.env.BALENA_CLOUD_API_KEY,
	},
}];
