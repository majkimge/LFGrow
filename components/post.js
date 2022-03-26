import React from 'react';
import Image from 'next/image';


const Post = ({ communityPicture, communityName, author, titleText, image }) => {
    return (
        <div className='postContainer' style={{ backgroundColor: 'lightgreen', width: '500px', padding: '1rem' }}>
            <div className='infoRow' style={{ marginLeft: '1rem' }}>

                <Image src={communityPicture} width={20} height={20} style={{ justifyContent: 'center' }} /> &nbsp;
                <b>{communityName}</b> &nbsp; &nbsp;
                Posted by: &nbsp; {author}
            </div>
            <div className='title'>
                <h3>{titleText}</h3>
            </div>
            <div className='img'>
                <Image src={image} />
            </div>
            <div className='buttons'>
                <button>
                    Comment
                </button>
            </div>
        </div>
    );
}

export { Post };